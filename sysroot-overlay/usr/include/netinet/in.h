#ifndef _NETINET_IN_H
#define _NETINET_IN_H

/*
 * Whole file inside one extern "C" block.  Without it, a C++ consumer gets
 * C++ linkage for htonl/htons/ntohl from here, and then <arpa/inet.h> --
 * which uv includes right after -- declares the same functions with C
 * linkage from its own extern "C" block.  That is a hard error:
 *     declaration of 'htonl' has a different language linkage
 */
#ifdef __cplusplus
extern "C" {
#endif

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in6.h>

#ifndef INET_ADDRSTRLEN
#define INET_ADDRSTRLEN 16
#endif

#ifndef INET6_ADDRSTRLEN
#define INET6_ADDRSTRLEN 46
#endif

#define IPPROTO_IP      0
#define IPPROTO_HOPOPTS 0
#define IPPROTO_ICMP    1
#define IPPROTO_IGMP    2
#define IPPROTO_IPIP    4
#define IPPROTO_TCP     6
#define IPPROTO_EGP     8
#define IPPROTO_PUP     12
#define IPPROTO_UDP     17
#define IPPROTO_IDP     22
#define IPPROTO_TP      29
#define IPPROTO_DCCP    33
#define IPPROTO_IPV6    41
#define IPPROTO_RSVP    46
#define IPPROTO_GRE     47
#define IPPROTO_ESP     50
#define IPPROTO_AH      51
#define IPPROTO_MTP     92
#define IPPROTO_BEETPH  94
#define IPPROTO_ENCAP   98
#define IPPROTO_PIM     103
#define IPPROTO_COMP    108
#define IPPROTO_SCTP    132
#define IPPROTO_UDPLITE 136
#define IPPROTO_MPLS    137
#define IPPROTO_RAW     255
#define IPPROTO_MAX     256

#define IN_PORT_ANY 0
#define IN_PORT_RESERVED 1024

struct in_addr {
    in_addr_t s_addr;
};

/* Lowest port number a privileged process may bind.  musl omits it; Dropbear's
 * tcp-forwarding check uses it to decide whether an unprivileged bind may
 * claim a reserved port.  Same value on Darwin and Linux. */
#ifndef IPPORT_RESERVED
#define IPPORT_RESERVED 1024
#endif

struct sockaddr_in {
	unsigned char	sin_len;	/* Darwin: total length (16) */
	sa_family_t	sin_family;
	in_port_t	sin_port;
	struct in_addr	sin_addr;
	char		sin_zero[8];
};




#define INADDR_ANY          ((in_addr_t)0x00000000)
#define INADDR_BROADCAST    ((in_addr_t)0xffffffff)
#define INADDR_LOOPBACK     0x7f000001

/* IN_LOOPBACKNET is a Linux-only name for the leading octet of the IPv4
   loopback block (127.0.0.0/8).  Darwin's <netinet/in.h> spells the block's
   class constants IN_CLASSA_NET etc. and never defines this name, and musl --
   whose header this overlay replaces -- does not either.  OpenSSH's
   sshconnect.c uses it to answer "is this address local?", so without this
   definition the build fails with "undeclared identifier IN_LOOPBACKNET".
   The value is not platform-specific: it is 127 on every system that names it,
   and it is what "(addr >> 24) == IN_LOOPBACKNET" in sockaddr_is_local()
   wants. */
#define IN_LOOPBACKNET 127
#define INADDR_NONE         0xffffffff

#define IN6ADDR_ANY_INIT { { { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 } } }
#define IN6ADDR_LOOPBACK_INIT { { { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1 } } }

extern const struct in6_addr in6addr_any;
extern const struct in6_addr in6addr_loopback;

uint32_t htonl(uint32_t);
uint16_t htons(uint16_t);
uint32_t ntohl(uint32_t);
uint16_t ntohs(uint16_t);

in_addr_t inet_addr(const char *);
int inet_aton(const char *, struct in_addr *);
char *inet_ntoa(struct in_addr);
int inet_pton(int, const char *__restrict, void *__restrict);
const char *inet_ntop(int, const void *__restrict, char *__restrict, socklen_t);

/*
 * IPv6 address-classification macros, taken from xnu-3789.70.16
 * bsd/netinet6/in6.h.  musl's <netinet/in.h> defines no IN6_IS_ADDR_*
 * (they live behind feature macros this sysroot does not enable), and
 * c-ares' ares_getnameinfo.c needs the multicast ones.
 */
#ifndef IN6_IS_ADDR_MC_LINKLOCAL
#define IN6_IS_ADDR_UNSPECIFIED(a) \
	((*(const uint32_t *)(const void *)(&(a)->s6_addr[0]) == 0) && \
	 (*(const uint32_t *)(const void *)(&(a)->s6_addr[4]) == 0) && \
	 (*(const uint32_t *)(const void *)(&(a)->s6_addr[8]) == 0) && \
	 (*(const uint32_t *)(const void *)(&(a)->s6_addr[12]) == 0))
#define IN6_IS_ADDR_LOOPBACK(a) \
	((*(const uint32_t *)(const void *)(&(a)->s6_addr[0]) == 0) && \
	 (*(const uint32_t *)(const void *)(&(a)->s6_addr[4]) == 0) && \
	 (*(const uint32_t *)(const void *)(&(a)->s6_addr[8]) == 0) && \
	 (*(const uint32_t *)(const void *)(&(a)->s6_addr[12]) == ntohl(1)))
#define IN6_IS_ADDR_V4MAPPED(a) \
	((*(const uint32_t *)(const void *)(&(a)->s6_addr[0]) == 0) && \
	 (*(const uint32_t *)(const void *)(&(a)->s6_addr[4]) == 0) && \
	 (*(const uint32_t *)(const void *)(&(a)->s6_addr[8]) == ntohl(0x0000ffff)))
#define IN6_IS_ADDR_LINKLOCAL(a) \
	(((a)->s6_addr[0] == 0xfe) && (((a)->s6_addr[1] & 0xc0) == 0x80))
#define IN6_IS_ADDR_SITELOCAL(a) \
	(((a)->s6_addr[0] == 0xfe) && (((a)->s6_addr[1] & 0xc0) == 0xc0))
#define IN6_IS_ADDR_MULTICAST(a)	((a)->s6_addr[0] == 0xff)
#define IN6_IS_ADDR_MC_NODELOCAL(a) \
	(IN6_IS_ADDR_MULTICAST(a) && (((a)->s6_addr[1] & 0x0f) == 1))
#define IN6_IS_ADDR_MC_LINKLOCAL(a) \
	(IN6_IS_ADDR_MULTICAST(a) && (((a)->s6_addr[1] & 0x0f) == 2))
#define IN6_IS_ADDR_MC_SITELOCAL(a) \
	(IN6_IS_ADDR_MULTICAST(a) && (((a)->s6_addr[1] & 0x0f) == 5))
#define IN6_IS_ADDR_MC_ORGLOCAL(a) \
	(IN6_IS_ADDR_MULTICAST(a) && (((a)->s6_addr[1] & 0x0f) == 8))
#define IN6_IS_ADDR_MC_GLOBAL(a) \
	(IN6_IS_ADDR_MULTICAST(a) && (((a)->s6_addr[1] & 0x0f) == 14))
#endif

/*
 * IPv4 socket and multicast options.
 *
 * musl defines none of these (they live behind feature macros this sysroot
 * does not enable) and c-ares needs the membership ones.  The values are
 * Darwin's, NOT Linux's -- this matters, because the two disagree:
 *
 *     option            Darwin  Linux
 *     IP_TTL               4      2
 *     IP_MULTICAST_IF      9      32
 *     IP_MULTICAST_TTL    10      33
 *     IP_MULTICAST_LOOP   11      34
 *
 * All values below are from xnu-3789.70.16 bsd/netinet/in.h.
 */
#ifndef IP_OPTIONS
#define IP_OPTIONS		1
#define IP_HDRINCL		2
#define IP_TOS			3
#define IP_TTL			4
#define IP_RECVOPTS		5
#define IP_RECVRETOPTS		6
#define IP_RECVDSTADDR		7
#define IP_RETOPTS		8
#define IP_MULTICAST_IF		9
#define IP_MULTICAST_TTL	10
#define IP_MULTICAST_LOOP	11
#define IP_ADD_MEMBERSHIP	12
#define IP_DROP_MEMBERSHIP	13
#define IP_MULTICAST_VIF	14
#define IP_RECVIF		20
#define IP_STRIPHDR		23
#define IP_RECVTTL		24
#define IP_MULTICAST_IFINDEX	66
#define IP_ADD_SOURCE_MEMBERSHIP	70
#define IP_DROP_SOURCE_MEMBERSHIP	71
#define IP_BLOCK_SOURCE		72
#define IP_UNBLOCK_SOURCE	73
#define IP_DEFAULT_MULTICAST_TTL	1
#define IP_DEFAULT_MULTICAST_LOOP	1
#define IP_MAX_MEMBERSHIPS	20
#endif

/*
 * IPv6 multicast options (xnu-3789.70.16 bsd/netinet6/in6.h).  IPV6_ADD_MEMBERSHIP
 * and IPV6_DROP_MEMBERSHIP are Darwin's older spellings of
 * IPV6_JOIN_GROUP / IPV6_LEAVE_GROUP, which share their values.
 */
#ifndef IPV6_UNICAST_HOPS
#define IPV6_UNICAST_HOPS	4
#define IPV6_MULTICAST_IF	9
#define IPV6_MULTICAST_HOPS	10
#define IPV6_MULTICAST_LOOP	11
#define IPV6_JOIN_GROUP		12
#define IPV6_LEAVE_GROUP	13
#define IPV6_ADD_MEMBERSHIP	IPV6_JOIN_GROUP
#define IPV6_DROP_MEMBERSHIP	IPV6_LEAVE_GROUP
#define IPV6_DEFAULT_MULTICAST_HOPS	1
#define IPV6_DEFAULT_MULTICAST_LOOP	1
#endif

/*
 * Argument structures for the multicast options below, with the layouts
 * from xnu-3789.70.16 bsd/netinet/in.h.
 *
 * xnu wraps ip_mreq_source in #pragma pack(4); three in_addr members are
 * 4-byte aligned on armv7 anyway so it is a no-op here, but it is kept
 * because dropping it would change the layout on a 64-bit target.
 */
#ifndef HAVE_STRUCT_IP_MREQ
#define HAVE_STRUCT_IP_MREQ
struct ip_mreq {
	struct in_addr	imr_multiaddr;	/* IP multicast address of group */
	struct in_addr	imr_interface;	/* local IP address of interface */
};

struct ip_mreqn {
	struct in_addr	imr_multiaddr;
	struct in_addr	imr_address;
	int		imr_ifindex;
};

#pragma pack(4)
struct ip_mreq_source {
	struct in_addr	imr_multiaddr;
	struct in_addr	imr_sourceaddr;
	struct in_addr	imr_interface;
};
#pragma pack()

struct group_req {
	uint32_t		gr_interface;	/* interface index */
	struct sockaddr_storage	gr_group;	/* group address */
};

struct group_source_req {
	uint32_t		gsr_interface;	/* interface index */
	struct sockaddr_storage	gsr_group;	/* group address */
	struct sockaddr_storage	gsr_source;	/* source address */
};
#endif /* HAVE_STRUCT_IP_MREQ */

/*
 * Source-specific multicast (RFC 3678), from xnu-3789.70.16
 * bsd/netinet/in.h.
 *
 * Darwin numbers these 80..85 -- nowhere near Linux's 42..49 band.  They
 * were first written here from the Linux range by assumption and had to be
 * corrected against xnu; the wrong values would not fail to compile, they
 * would silently hand the wrong option to setsockopt().
 */
#ifndef MCAST_JOIN_GROUP
#define MCAST_JOIN_GROUP		80
#define MCAST_LEAVE_GROUP		81
#define MCAST_JOIN_SOURCE_GROUP		82
#define MCAST_LEAVE_SOURCE_GROUP	83
#define MCAST_BLOCK_SOURCE		84
#define MCAST_UNBLOCK_SOURCE		85
#define MCAST_UNDEFINED			0
#define MCAST_INCLUDE			1
#define MCAST_EXCLUDE			2
#endif

#ifdef __cplusplus
}
#endif

#endif /* _NETINET_IN_H */
