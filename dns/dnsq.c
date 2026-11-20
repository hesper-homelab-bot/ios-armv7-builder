/*
 * dnsq.c — dig / nslookup / host for armv7 iOS 10.x, one binary three names.
 *
 * The device ships zero DNS clients (probed 2026-11-20: dig/nslookup/host/
 * dnsdomainname all absent), and DNS debugging kept falling back to the host.
 * This is a self-contained stub resolver: UDP to the resolver with retries,
 * TCP fallback when the TC bit is set, name-compression-aware RR parsing,
 * and the record set that actually shows up in debugging (A/AAAA/CNAME/MX/
 * TXT/NS/PTR/SOA/ANY).
 *
 * argv[0] selects the frontend, mirroring the three classic tools:
 *   dig @server name [type] [+short]     — zone-literate output
 *   nslookup name [server]               — two-line answer style
 *   host name [server]                   — one-line-per-record style
 *
 * Resolver discovery: /etc/resolv.conf nameserver lines (iOS regenerates
 * that file from the System Configuration when the network changes).
 */
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define DNS_PORT	53
#define MAXPACKET	65536
#define MAXTRIES	2
#define TIMEOUT_SEC	3

/* Record types we render. */
#define T_A		1
#define T_NS		2
#define T_CNAME		5
#define T_SOA		6
#define T_PTR		12
#define T_MX		15
#define T_TXT		16
#define T_AAAA		28
#define T_ANY		255

static const char *
typename(int t)
{
	switch (t) {
	case T_A:	return "A";
	case T_NS:	return "NS";
	case T_CNAME:	return "CNAME";
	case T_SOA:	return "SOA";
	case T_PTR:	return "PTR";
	case T_MX:	return "MX";
	case T_TXT:	return "TXT";
	case T_AAAA:	return "AAAA";
	case T_ANY:	return "ANY";
	default:	return "TYPE?";
	}
}

static int
typecode(const char *s)
{
	if (!s) return T_A;
	if (!strcasecmp(s, "a")) return T_A;
	if (!strcasecmp(s, "aaaa")) return T_AAAA;
	if (!strcasecmp(s, "cname")) return T_CNAME;
	if (!strcasecmp(s, "mx")) return T_MX;
	if (!strcasecmp(s, "txt")) return T_TXT;
	if (!strcasecmp(s, "ns")) return T_NS;
	if (!strcasecmp(s, "ptr")) return T_PTR;
	if (!strcasecmp(s, "soa")) return T_SOA;
	if (!strcasecmp(s, "any")) return T_ANY;
	if (atoi(s) > 0) return atoi(s);
	return -1;
}

/* ---------------------------------------------------------- wire helpers */

#define DNSHDR_LEN 12

static void
put_u16(unsigned char *p, unsigned v)
{
	p[0] = (unsigned char)(v >> 8);
	p[1] = (unsigned char)v;
}

static unsigned
get_u16(const unsigned char *p)
{
	return ((unsigned)p[0] << 8) | p[1];
}

/* Encode a dotted name into DNS wire format at p; returns bytes written. */
static size_t
encode_name(const char *name, unsigned char *p, size_t left)
{
	size_t used = 0;
	const char *s = name;

	while (*s) {
		const char *dot = strchr(s, '.');
		size_t lab = dot ? (size_t)(dot - s) : strlen(s);
		if (lab == 0 || lab > 63 || used + 1 + lab + 1 > left)
			return 0;
		p[used++] = (unsigned char)lab;
		memcpy(p + used, s, lab);
		used += lab;
		if (!dot) break;
		s = dot + 1;
	}
	if (used + 1 > left)
		return 0;
	p[used++] = 0;	/* root */
	return used;
}

/*
 * Decode a (possibly compressed) name at wire[offset] into out.
 * *offset advances past the name AS CONSUMED IN PLACE (jumped-to targets
 * advance a local cursor; the caller's offset follows the outer loop, the
 * standard two-variable dance).
 */
static size_t
decode_name(const unsigned char *msg, size_t msglen, size_t *offset,
    char *out, size_t outsz)
{
	size_t pos = *offset, written = 0, jumps = 0;
	int done = 0;

	out[0] = '\0';
	while (!done) {
		if (pos >= msglen)
			return 0;
		unsigned char len = msg[pos];
		if (len == 0) {
			pos += 1;
			done = 1;
		} else if ((len & 0xc0) == 0xc0) {	/* compression pointer */
			if (pos + 1 >= msglen || jumps++ > 32)
				return 0;
			size_t target = ((size_t)(len & 0x3f) << 8) | msg[pos + 1];
			if (written == 0)
				*offset = pos + 2;	/* consume on first jump */
			pos = target;
			if (pos >= msglen)
				return 0;
		} else {
			if (pos + 1 + len > msglen ||
			    written + len + 2 > outsz)
				return 0;
			memcpy(out + written, msg + pos + 1, len);
			written += len;
			out[written++] = '.';
			pos += 1 + len;
		}
	}
	if (written && out[written - 1] == '.')
		out[written - 1] = '\0';		/* drop trailing dot */
	if (written == 0)
		strlcpy(out, ".", outsz);
	if (written == 0 || out[0] == '\0')
		;
	/* If we never jumped, the cursor sits past the whole name. */
	if (*offset <= pos && jumps == 0)
		*offset = pos;
	return written;
}

/* ------------------------------------------------------------ resolver io */

static int
resolv_conf_server(char *out, size_t outsz)
{
	FILE *f = fopen("/etc/resolv.conf", "r");
	char line[256];

	if (f == NULL)
		return -1;
	while (fgets(line, sizeof(line), f)) {
		if (!strncmp(line, "nameserver", 10) &&
		    (line[10] == ' ' || line[10] == '\t')) {
			char *s = line + 10;
			while (*s == ' ' || *s == '\t') s++;
			s[strcspn(s, " \t\n")] = '\0';
			strlcpy(out, s, outsz);
			fclose(f);
			return 0;
		}
	}
	fclose(f);
	return -1;
}

/* One query over UDP; returns packet length or -1.  On TC, caller retries TCP. */
static ssize_t
udp_query(const char *server, const unsigned char *q, size_t qlen,
    unsigned char *resp, size_t respmax)
{
	struct sockaddr_in sa;
	struct timeval tv = { TIMEOUT_SEC, 0 };
	int fd, n;

	fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd < 0)
		return -1;
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	memset(&sa, 0, sizeof(sa));
	sa.sin_family = AF_INET;
	sa.sin_port = htons(DNS_PORT);
	if (inet_pton(AF_INET, server, &sa.sin_addr) != 1) {
		close(fd);
		return -1;
	}
	for (int attempt = 0; attempt < MAXTRIES; attempt++) {
		if (sendto(fd, q, qlen, 0, (struct sockaddr *)&sa, sizeof(sa))
		    != (ssize_t)qlen) {
			close(fd);
			return -1;
		}
		n = recv(fd, resp, respmax, 0);
		if (n >= (int)DNSHDR_LEN)
			return n;	/* caller checks id + TC */
		if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
			break;
	}
	close(fd);
	return -1;
}

static ssize_t
tcp_query(const char *server, const unsigned char *q, size_t qlen,
    unsigned char *resp, size_t respmax)
{
	struct sockaddr_in sa;
	struct timeval tv = { TIMEOUT_SEC, 0 };
	unsigned char hdr[2];
	int fd;
	ssize_t n;
	unsigned want;

	fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0)
		return -1;
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
	memset(&sa, 0, sizeof(sa));
	sa.sin_family = AF_INET;
	sa.sin_port = htons(DNS_PORT);
	if (inet_pton(AF_INET, server, &sa.sin_addr) != 1) {
		close(fd);
		return -1;
	}
	if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
		close(fd);
		return -1;
	}
	hdr[0] = (unsigned char)(qlen >> 8);
	hdr[1] = (unsigned char)qlen;
	if (write(fd, hdr, 2) != 2 || write(fd, q, qlen) != (ssize_t)qlen) {
		close(fd);
		return -1;
	}
	if (read(fd, hdr, 2) != 2) {
		close(fd);
		return -1;
	}
	want = ((unsigned)hdr[0] << 8) | hdr[1];
	if (want > respmax)
		want = respmax;
	n = read(fd, resp, want);
	close(fd);
	return n;
}

/* ------------------------------------------------------------- rendering */

static const char *
rcode_name(int rcode)
{
	static const char *names[] = { "NOERROR", "FORMERR", "SERVFAIL",
	    "NXDOMAIN", "NOTIMP", "REFUSED" };
	if (rcode < 6)
		return names[rcode];
	return "RCODE?";
}

static void
render_rdata(const unsigned char *msg, size_t msglen, size_t *pos,
    int type, unsigned rdlength, char *out, size_t outsz)
{
	size_t end = *pos + rdlength;

	out[0] = '\0';
	switch (type) {
	case T_A:
		if (rdlength == 4)
			snprintf(out, outsz, "%u.%u.%u.%u", msg[*pos], msg[*pos+1],
			    msg[*pos+2], msg[*pos+3]);
		break;
	case T_AAAA:
		if (rdlength == 16) {
			char abuf[64];
			inet_ntop(AF_INET6, msg + *pos, abuf, sizeof(abuf));
			strlcpy(out, abuf, outsz);
		}
		break;
	case T_CNAME:
	case T_NS:
	case T_PTR: {
		size_t at = *pos;
		char name[512];
		if (decode_name(msg, msglen, &at, name, sizeof(name)))
			strlcpy(out, name, outsz);
		break;
	}
	case T_MX:
		if (rdlength >= 3) {
			size_t at = *pos + 2;
			char name[512];
			unsigned pref = get_u16(msg + *pos);
			if (decode_name(msg, msglen, &at, name, sizeof(name)))
				snprintf(out, outsz, "%u %s", pref, name);
		}
		break;
	case T_TXT:
		if (rdlength >= 1) {
			size_t at = *pos, o = 0;
			out[0] = '\0';
			while (at < end && o + 2 < outsz) {
				unsigned l = msg[at++];
				if (at + l > end) break;
				out[o++] = '"';
				for (unsigned k = 0; k < l && o + 3 < outsz; k++) {
					unsigned char c = msg[at + k];
					out[o++] = (c >= 0x20 && c < 0x7f) ? c : '.';
				}
				out[o++] = '"';
				at += l;
				if (at < end) out[o++] = ' ';
			}
			out[o] = '\0';
		}
		break;
	case T_SOA:
		if (rdlength > 20) {
			size_t at = *pos;
			char mname[512], rname[512];
			unsigned serial, refresh, retry, expire, minimum;
			if (decode_name(msg, msglen, &at, mname, sizeof(mname)) &&
			    decode_name(msg, msglen, &at, rname, sizeof(rname)) &&
			    at + 20 <= end) {
				serial = get_u16(msg + at) << 16 | get_u16(msg + at + 2);
				refresh = get_u16(msg + at + 4) << 16 | get_u16(msg + at + 6);
				retry = get_u16(msg + at + 8) << 16 | get_u16(msg + at + 10);
				expire = get_u16(msg + at + 12) << 16 | get_u16(msg + at + 14);
				minimum = get_u16(msg + at + 16) << 16 | get_u16(msg + at + 18);
				snprintf(out, outsz,
				    "%s %s serial=%u refresh=%u retry=%u expire=%u minimum=%u",
				    mname, rname, serial, refresh, retry, expire, minimum);
			}
		}
		break;
	default:
		snprintf(out, outsz, "\\# %u", rdlength);	/* RFC 3597 unknown */
		break;
	}
	*pos = end;
}

/* --------------------------------------------------------------- queries */

static int qid;

struct dnsanswer {
	unsigned char pkt[MAXPACKET];
	ssize_t len;
	int rcode;
	unsigned anscount;
};

static int
ask(const char *server, const char *name, int qtype, struct dnsanswer *out)
{
	unsigned char q[512];
	size_t qlen, namelen;
	ssize_t n;
	int tc = 0;

	memset(out, 0, sizeof(*out));
	q[0] = (unsigned char)((++qid) >> 8);
	q[1] = (unsigned char)qid;
	put_u16(q + 2, 0x0100);
	put_u16(q + 4, 1);
	namelen = encode_name(name, q + DNSHDR_LEN, sizeof(q) - DNSHDR_LEN - 4);
	if (namelen == 0) {
		errno = EMSGSIZE;
		return -1;
	}
	put_u16(q + DNSHDR_LEN + namelen, qtype);
	put_u16(q + DNSHDR_LEN + namelen + 2, 1);
	qlen = DNSHDR_LEN + namelen + 4;

	n = udp_query(server, q, qlen, out->pkt, sizeof(out->pkt));
	if (n < 0)
		return -1;
	if (get_u16(out->pkt) != (unsigned)qid)
		return -1;
	tc = (get_u16(out->pkt + 2) >> 9) & 1;
	if (tc)
		n = tcp_query(server, q, qlen, out->pkt, sizeof(out->pkt));
	if (n < 0)
		return -1;
	out->len = n;
	out->rcode = get_u16(out->pkt + 2) & 0x0f;
	out->anscount = get_u16(out->pkt + 6);
	return 0;
}

/* Walk answer records, render each; print via the frontend callback. */
typedef void (*rr_fn)(const char *name, int type, unsigned ttl,
    const char *rdata, void *ctx);

static int
walk_answers(const struct dnsanswer *a, rr_fn fn, void *ctx)
{
	const unsigned char *msg = a->pkt;
	size_t msglen = (size_t)a->len;
	size_t pos = DNSHDR_LEN;
	unsigned qd = get_u16(msg + 4), an = get_u16(msg + 6);
	char name[512];
	unsigned i;

	/* skip question section */
	for (i = 0; i < qd; i++) {
		if (!decode_name(msg, msglen, &pos, name, sizeof(name)))
			return -1;
		pos += 4;
	}
	for (i = 0; i < an; i++) {
		int type;
		unsigned ttl, rdlength;
		char rdata[1024];
		if (!decode_name(msg, msglen, &pos, name, sizeof(name)))
			return -1;
		if (pos + 10 > msglen)
			return -1;
		type = (int)get_u16(msg + pos);
		ttl = (get_u16(msg + pos + 4) << 16) | get_u16(msg + pos + 6);
		rdlength = get_u16(msg + pos + 8);
		pos += 10;
		if (pos + rdlength > msglen)
			return -1;
		render_rdata(msg, msglen, &pos, type, rdlength, rdata, sizeof(rdata));
		fn(name, type, ttl, rdata, ctx);
	}
	return (int)an;
}

/* -------------------------------------------------------------- frontends */

static int opt_short;

static void
dig_rr(const char *name, int type, unsigned ttl, const char *rdata, void *ctx)
{
	(void)ctx;
	if (opt_short) {
		printf("%s\n", rdata);
		return;
	}
	printf("%s\t%u\tIN\t%s\t%s\n", name, ttl, typename(type), rdata);
}

static void
host_rr(const char *name, int type, unsigned ttl, const char *rdata, void *ctx)
{
	(void)ttl; (void)ctx;
	if (type == T_A)
		printf("%s has address %s\n", name, rdata);
	else if (type == T_AAAA)
		printf("%s has IPv6 address %s\n", name, rdata);
	else if (type == T_CNAME)
		printf("%s is an alias for %s\n", name, rdata);
	else if (type == T_MX)
		printf("%s mail is handled by %s\n", name, rdata);
	else if (type == T_TXT)
		printf("%s descriptive text %s\n", name, rdata);
	else if (type == T_NS)
		printf("%s name server %s\n", name, rdata);
	else if (type == T_PTR)
		printf("%s domain name pointer %s\n", name, rdata);
	else
		printf("%s has %s record %s\n", name, typename(type), rdata);
}

static void
nslookup_rr(const char *name, int type, unsigned ttl, const char *rdata,
    void *ctx)
{
	(void)ttl; (void)ctx;
	printf("Name: %s\n", name);
	printf("%s: %s\n", typename(type), rdata);
}

static int
run_frontend(const char *server, const char *name, int qtype, int frontend)
{
	struct dnsanswer a;
	rr_fn fn = dig_rr;
	int n;

	if (frontend == 1) fn = host_rr;
	if (frontend == 2) fn = nslookup_rr;

	if (ask(server, name, qtype, &a) != 0) {
		fprintf(stderr, "%s: query to %s failed: %s\n",
		    frontend == 1 ? "host" : (frontend == 2 ? "nslookup" : "dig"),
		    server, strerror(errno));
		return 2;
	}
	if (frontend == 2)
		printf("Server:\t\t%s\n", server);
	if (opt_short && frontend == 0) {
		;	/* dig +short prints only rdata */
	} else if (frontend == 0) {
		printf("; <<>> dnsq (dig-lite) @%s\n", server);
		printf(";; QUESTION SECTION:\n;%s.\t\tIN\t%s\n\n", name,
		    typename(qtype));
		printf(";; ANSWER SECTION:\n");
	}
	if (a.rcode != 0) {
		if (frontend == 0 && !opt_short)
			printf(";; %s\n", rcode_name(a.rcode));
		else
			fprintf(stderr, "%s\n", rcode_name(a.rcode));
		return a.rcode == 3 ? 1 : 2;
	}
	n = walk_answers(&a, fn, NULL);
	if (n == 0 && frontend != 0)
		fprintf(stderr, "%s has no %s record\n", name, typename(qtype));
	if (n == 0)
		return 1;
	return 0;
}

static void
usage(const char *self)
{
	fprintf(stderr,
	    "usage (as dig):    %s [@server] name [type] [+short]\n"
	    "usage (as nslookup): %s name [server]\n"
	    "usage (as host):   %s name [server]\n"
	    "types: a aaaa cname mx txt ns ptr soa any\n",
	    self, self, self);
}

int
main(int argc, char **argv)
{
	const char *base = strrchr(argv[0], '/');
	base = base ? base + 1 : argv[0];
	int frontend = 0;	/* 0 dig, 1 host, 2 nslookup */
	const char *server = NULL, *name = NULL, *typestr = NULL;
	char serverbuf[64];
	int qtype;

	if (!strcmp(base, "host")) frontend = 1;
	if (!strcmp(base, "nslookup")) frontend = 2;
	if (!strcmp(base, "dig")) frontend = 0;

	argv++; argc--;
	while (argc > 0) {
		char *a = argv[0];
		if (!strcmp(a, "-t") && argc > 1) {
			typestr = argv[1];
			argv++; argc--;
		} else if (a[0] == '@') {
			server = a + 1;
		} else if (frontend == 0 && !strncmp(a, "+short", 6)) {
			opt_short = 1;
		} else if (!strcmp(a, "+short")) {
			opt_short = 1;
		} else if (name == NULL) {
			name = a;
		} else if (typestr == NULL) {
			typestr = a;
		} else if (server == NULL) {
			server = a;
		} else {
			usage(base);
			return 2;
		}
		argv++; argc--;
	}
	if (name == NULL) {
		usage(base);
		return 2;
	}
	if (server == NULL) {
		if (resolv_conf_server(serverbuf, sizeof(serverbuf)) != 0) {
			fprintf(stderr, "no nameserver: pass @server or fix "
			    "/etc/resolv.conf\n");
			return 2;
		}
		server = serverbuf;
	}
	qtype = typecode(typestr);
	if (qtype < 0) {
		fprintf(stderr, "unknown type %s\n", typestr);
		return 2;
	}
	return run_frontend(server, name, qtype, frontend);
}
