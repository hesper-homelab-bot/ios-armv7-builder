/*
 * ping for armv7 iOS 10.x -- minimal ICMP echo implementation.
 *
 * Transport: SOCK_DGRAM + IPPROTO_ICMP, an *unprivileged* ICMP socket.
 * iOS 10 rejects SOCK_RAW for non-root processes; the datagram form is
 * allowed for everyone (probed on the device, 2026-11-19).  The kernel
 * builds the IP header; we write the ICMP header + payload and match
 * replies by ICMP id + seq.  On a datagram ICMP socket recv() returns the
 * ICMP header onward (no IP header); TTL arrives via IP_RECVTTL cmsg.
 *
 * No upstream: iputils is Linux-only (libcap, raw sockets), OpenBSD's ping
 * assumes setuid+raw, Apple's is not open source.  Semantics follow the
 * common ping CLI: -c count -i interval -s size -W timeout_ms host.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <time.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>

#define DEFAULT_INTERVAL 1.0
#define DEFAULT_SIZE	 56	/* ICMP payload */
#define DEFAULT_TIMEOUT	 10000	/* ms, per-packet wait cap */
#define SEQTAB		 4096

static int		sockfd;
static uint16_t		ident;
static int		ntransmitted, nreceived, nduplicated;
static int		timing = 1;
static double		tmin = 1e9, tmax = 0.0, tsum = 0.0;
static double		t_sent[SEQTAB];		/* send time per seq (wrap) */
static unsigned char	rcvd[SEQTAB];
static volatile sig_atomic_t finished;

static void
stopit(int sig)
{
	(void)sig;
	finished = 1;
}

static uint16_t
cksum(unsigned char *p, int len)
{
	unsigned long sum = 0;
	while (len > 1) {
		/* little-endian accumulation: the result is the wire-order
		 * value, assignable straight to n_short on a LE target */
		sum += p[0] | (p[1] << 8);
		p += 2;
		len -= 2;
	}
	if (len == 1)
		sum += p[0];
	while (sum >> 16)
		sum = (sum & 0xffff) + (sum >> 16);
	return (uint16_t)(~sum & 0xffff);
}

static double
now(void)
{
	struct timeval tv;
	gettimeofday(&tv, 0);
	return tv.tv_sec + tv.tv_usec / 1e6;
}

static void
fill_icmp(unsigned char *pkt, int seq, int datalen)
{
	struct icmp *ic = (struct icmp *)pkt;

	memset(pkt, 0, ICMP_MINLEN + datalen);
	ic->icmp_type = ICMP_ECHO;
	ic->icmp_code = 0;
	ic->icmp_id = htons(ident);
	ic->icmp_seq = htons((unsigned short)seq);
	/* payload: marker word + send timestamp (echoed back for rtt) */
	{
		struct timeval tv;
		gettimeofday(&tv, NULL);
		memcpy(pkt + ICMP_MINLEN, "ipng", 4);
		memcpy(pkt + ICMP_MINLEN + 4, &tv, sizeof(tv));
	}
	ic->icmp_cksum = 0;
	ic->icmp_cksum = cksum(pkt, ICMP_MINLEN + datalen);
}

int
main(int argc, char **argv)
{
	struct addrinfo hints, *res = NULL;
	struct sockaddr_in target;
	double interval = DEFAULT_INTERVAL;
	int datalen = DEFAULT_SIZE;
	int count = 0;			/* 0 = forever */
	int timeout_ms = DEFAULT_TIMEOUT;
	int ch, seq = 0;
	char *host;
	char ipstr[64];

	while ((ch = getopt(argc, argv, "c:i:s:W:")) != -1)
		switch (ch) {
		case 'c':
			count = atoi(optarg);
			if (count < 0) count = 0;
			break;
		case 'i':
			interval = atof(optarg);
			if (interval < 0.01)
				interval = 0.01;
			break;
		case 's':
			datalen = atoi(optarg);
			if (datalen < 8)
				datalen = 8;
			break;
		case 'W':
			timeout_ms = atoi(optarg);
			break;
		default:
			fprintf(stderr,
			    "usage: ping [-c count] [-i sec] [-s size]"
			    " [-W ms] host\n");
			return 2;
		}
	argc -= optind;
	argv += optind;
	if (argc != 1) {
		fprintf(stderr, "usage: ping [-c count] [-i sec] [-s size]"
		    " [-W ms] host\n");
		return 2;
	}
	host = argv[0];

	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_DGRAM;
	if (getaddrinfo(host, NULL, &hints, &res) != 0 || res == NULL) {
		fprintf(stderr, "ping: cannot resolve %s\n", host);
		return 2;
	}
	memset(&target, 0, sizeof(target));
	memcpy(&target, res->ai_addr, sizeof(target));
	freeaddrinfo(res);
	if (inet_ntop(AF_INET, &target.sin_addr, ipstr, sizeof(ipstr)) == NULL)
		snprintf(ipstr, sizeof(ipstr), "?");

	if ((sockfd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP)) < 0) {
		/* non-root: dgram sends but iOS 10 never delivers echoreplies
		 * to dgram icmp sockets (probed) -- report and exit. */
		fprintf(stderr, "ping: raw icmp socket: %s\n"
		    " (this ping needs root: SOCK_RAW; the unprivileged"
		    " SOCK_DGRAM form cannot receive replies on iOS 10)\n",
		    strerror(errno));
		return 1;
	}
	{
		int on = 1;
		setsockopt(sockfd, IPPROTO_IP, IP_RECVTTL, &on, sizeof(on));
	}

	ident = (uint16_t)(getpid() & 0xffff) | 0x8000;
	memset(t_sent, 0, sizeof(t_sent));

	printf("PING %s (%s): %d data bytes (icmp dgram)\n",
	    host, ipstr, datalen);

	signal(SIGINT, stopit);
	signal(SIGTERM, stopit);

	while (!finished && (count == 0 || seq < count)) {
		unsigned char pkt[ICMP_MINLEN + 65536];
		unsigned char ctrl[512];
		struct icmp *ic = (struct icmp *)pkt;
		struct iovec iov = { pkt, sizeof(pkt) };
		struct msghdr mh;
		struct timeval tv;
		double t0, rtt = 0;
		int ttl = -1;
		int n, sidx;
		char *p = NULL;

		seq++;
		sidx = seq & (SEQTAB - 1);
		fill_icmp(pkt, seq, datalen);
		{
			struct timeval sv;
			gettimeofday(&sv, NULL);
			t_sent[sidx] = sv.tv_sec + sv.tv_usec / 1e6;
		}
		t0 = now();
		if (sendto(sockfd, pkt, ICMP_MINLEN + datalen, 0,
		    (struct sockaddr *)&target, sizeof(target)) < 0) {
			printf("sendto: %s\n", strerror(errno));
			if (errno == EACCES || errno == EPERM)
				break;
			goto settle;
		}
		ntransmitted++;

wait_again:
		{
			fd_set rf;
			struct timeval to;
			double waited = (now() - t0) * 1e3;
			long left = timeout_ms - (long)waited;
			if (left <= 0) {
				printf("Request timeout for icmp_seq %d\n",
				    seq);
				goto settle;
			}
			FD_ZERO(&rf);
			FD_SET(sockfd, &rf);
			to.tv_sec = left / 1000;
			to.tv_usec = (left % 1000) * 1000;
			n = select(sockfd + 1, &rf, 0, 0, &to);
			if (n <= 0) {
				printf("Request timeout for icmp_seq %d\n",
				    seq);
				goto settle;
			}
		}
		memset(&mh, 0, sizeof(mh));
		iov.iov_base = pkt;
		iov.iov_len = sizeof(pkt);
		mh.msg_iov = &iov;
		mh.msg_iovlen = 1;
		mh.msg_control = ctrl;
		mh.msg_controllen = sizeof(ctrl);
		n = recvmsg(sockfd, &mh, 0);
		if (n < (int)(ICMP_MINLEN + 4 + sizeof(struct timeval)))
			goto wait_again;	/* short: keep waiting */
		for (struct cmsghdr *cm = CMSG_FIRSTHDR(&mh); cm;
		    cm = CMSG_NXTHDR(&mh, cm)) {
			if (cm->cmsg_level == IPPROTO_IP &&
			    cm->cmsg_type == IP_RECVTTL && cm->cmsg_len >= CMSG_LEN(sizeof(int)))
				memcpy(&ttl, CMSG_DATA(cm), sizeof(int));
		}
		/* SOCK_RAW recv: IP header always present. */
		{
			unsigned char *ib = pkt;
			int il = n;
			if (n >= 20 && (pkt[0] >> 4) == 4) {
				int ihl = (pkt[0] & 0x0f) * 4;
				ib = pkt + ihl;
				il = n - ihl;
				if (ttl < 0) ttl = pkt[8];
			}
			if (getenv("PING_DEBUG")) {
				printf("dbg: n=%d b0=0x%02x icmp_type=%d\n",
				    n, pkt[0], ib[0]);
			}
			ic = (struct icmp *)ib;
			if (il < (int)(ICMP_MINLEN + 4 + sizeof(struct timeval)))
				goto wait_again;
			if (ic->icmp_type != ICMP_ECHOREPLY ||
			    ic->icmp_id != htons(ident))
				goto wait_again;
			p = ib;		/* payload offsets move with it */
		}
		{
			int rs = (int)ntohs(ic->icmp_seq);
			struct timeval sent, nowv;
			if (rs < 1 || rs > ntransmitted)
				goto wait_again;
			sidx = rs & (SEQTAB - 1);
			if (t_sent[sidx] <= 0)
				goto wait_again;
			memcpy(&sent, p + ICMP_MINLEN + 4, sizeof(sent));
			gettimeofday(&nowv, NULL);
			rtt = (nowv.tv_sec - sent.tv_sec) * 1e3
			    + (nowv.tv_usec - sent.tv_usec) / 1e3;
			if (rcvd[sidx]) {
				nduplicated++;
				printf("dup! %d bytes from %s: icmp_seq=%d"
				    " time=%.3f ms\n", n, ipstr, rs, rtt);
				goto settle;
			}
			rcvd[sidx] = 1;
			nreceived++;
			if (rtt < tmin) tmin = rtt;
			if (rtt > tmax) tmax = rtt;
			tsum += rtt;
			printf("%d bytes from %s: icmp_seq=%d ttl=%d"
			    " time=%.3f ms\n",
			    n, ipstr, rs, ttl, rtt);
		}

settle:
		(void)tv;
		(void)rtt;
		if (finished)
			break;
		{
			double slept = 0;
			while (slept < interval && !finished) {
				struct timespec ts = { 0, 100 * 1000 * 1000 };
				nanosleep(&ts, NULL);
				slept += 0.1;
			}
		}
	}

	printf("--- %s ping statistics ---\n", host);
	printf("%d packets transmitted, %d received, %d dup,"
	    " %d%% packet loss\n",
	    ntransmitted, nreceived, nduplicated,
	    ntransmitted ? (ntransmitted - nreceived) * 100 / ntransmitted : 0);
	if (nreceived) {
		printf("round-trip min/avg/max = %.3f/%.3f/%.3f ms\n",
		    tmin, tsum / nreceived, tmax);
	}
	close(sockfd);
	return nreceived ? 0 : 1;
}
