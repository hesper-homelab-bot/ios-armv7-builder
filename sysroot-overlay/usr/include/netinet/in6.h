#ifndef _NETINET_IN6_H
#define _NETINET_IN6_H

#include <sys/socket.h>
#include <stdint.h>

#define INET6_ADDRSTRLEN 46

struct in6_addr {
    union {
        uint8_t __u6_addr8[16];
        uint16_t __u6_addr16[8];
        uint32_t __u6_addr32[4];
    } __u6_addr;
};

#define s6_addr __u6_addr.__u6_addr8

struct sockaddr_in6 {
	unsigned char	sin6_len;
	sa_family_t	sin6_family;
	in_port_t	sin6_port;
	uint32_t	sin6_flowinfo;
	struct in6_addr	sin6_addr;
	uint32_t	sin6_scope_id;
};

#define IN6ADDR_ANY_INIT { { { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 } } }

/*
 * Argument structure for IPV6_JOIN_GROUP / IPV6_LEAVE_GROUP (and Darwin's
 * IPV6_ADD_MEMBERSHIP / IPV6_DROP_MEMBERSHIP spellings), from
 * xnu-3789.70.16 bsd/netinet6/in6.h.  Note the interface is an index
 * (unsigned int), not an address as in the IPv4 ip_mreq.
 */
struct ipv6_mreq {
	struct in6_addr	ipv6mr_multiaddr;
	unsigned int	ipv6mr_interface;
};
#define IN6ADDR_LOOPBACK_INIT { { { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1 } } }

extern const struct in6_addr in6addr_any;
extern const struct in6_addr in6addr_loopback;

#define IN6_IS_ADDR_UNSPECIFIED(a) \
    ((*(const uint32_t *)(a) == 0) && \
     (*(const uint32_t *)((const char *)(a)+4) == 0) && \
     (*(const uint32_t *)((const char *)(a)+8) == 0) && \
     (*(const uint32_t *)((const char *)(a)+12) == 0))

#define IN6_IS_ADDR_LOOPBACK(a) \
    ((*(const uint32_t *)(a) == 0) && \
     (*(const uint32_t *)((const char *)(a)+4) == 0) && \
     (*(const uint32_t *)((const char *)(a)+8) == 0) && \
     (*(const uint32_t *)((const char *)(a)+12) == ntohl(1)))

/* POSIX requires IN6_ARE_ADDR_EQUAL, but musl only ships the IN6_IS_ADDR_*
   predicates above.  wget's host.c calls it (comparing two v6 addresses) and
   fails to compile with "call to undeclared function".  Byte comparison is
   what every implementation does. */
#ifndef IN6_ARE_ADDR_EQUAL
#define IN6_ARE_ADDR_EQUAL(a, b) \
    (__builtin_memcmp((const void *)(a), (const void *)(b), \
                      sizeof(struct in6_addr)) == 0)
#endif

#define IN6_IS_ADDR_MULTICAST(a) (((const uint8_t *)(a))[0] == 0xff)
#define IN6_IS_ADDR_LINKLOCAL(a) \
    (((*(const uint32_t *)(a) & ntohl(0xffc00000)) == ntohl(0xfe800000)))
#define IN6_IS_ADDR_SITELOCAL(a) \
    (((*(const uint32_t *)(a) & ntohl(0xffc00000)) == ntohl(0xfec00000)))
#define IN6_IS_ADDR_V4MAPPED(a) \
    ((*(const uint32_t *)(a) == 0) && \
     (*(const uint32_t *)((const char *)(a)+4) == 0) && \
     (*(const uint32_t *)((const char *)(a)+8) == ntohl(0xffff)))
#define IN6_IS_ADDR_V4COMPAT(a) \
    ((*(const uint32_t *)(a) == 0) && \
     (*(const uint32_t *)((const char *)(a)+4) == 0) && \
     (*(const uint32_t *)((const char *)(a)+8) == 0) && \
     (*(const uint32_t *)((const char *)(a)+12) != 0) && \
     (*(const uint32_t *)((const char *)(a)+12) != ntohl(1)))

#endif

/* ===== DARWIN_OVERRIDES: RFC 3542 socket options and ancillary data =====
 * Values from xnu bsd/netinet/in6.h.  NOTE these differ from Linux
 * (IPV6_PKTINFO is 46 here, 50 on Linux; IPV6_RECVPKTINFO 61 vs 49).
 * Verified with a live setsockopt() probe on the target device.
 */
#ifndef __DARWIN_IN6_PKTINFO_DEFINED
#define __DARWIN_IN6_PKTINFO_DEFINED
struct in6_pktinfo {
	struct in6_addr	ipi6_addr;	/* src transport address */
	unsigned int	ipi6_ifindex;	/* interface index */
};
#endif

#undef IPV6_PKTINFO
#define IPV6_PKTINFO		46	/* in6_pktinfo; send if, src addr */
#undef IPV6_RECVPKTINFO
#define IPV6_RECVPKTINFO	61	/* bool; recv if index and dst addr */
#undef IPV6_HOPLIMIT
#define IPV6_HOPLIMIT		47	/* int; send hop limit */
#undef IPV6_RECVHOPLIMIT
#define IPV6_RECVHOPLIMIT	49
#undef IPV6_TCLASS
#define IPV6_TCLASS		36	/* int; send traffic class priority */
#undef IPV6_RECVTCLASS
#define IPV6_RECVTCLASS		57
#undef IPV6_DONTFRAG
#define IPV6_DONTFRAG		62
/* ===== end DARWIN_OVERRIDES ===== */

/* ---- IPv6 socket-option constants (values from xnu-3789.70.16
 * bsd/netinet6/in6.h, RFC 3542 spelling).  Guarded per-macro because musl
 * already defines some of them. ---- */
#ifndef IPV6_ADDR_INT32_ONE
#define IPV6_ADDR_INT32_ONE 1
#endif
#ifndef IPV6_ADDR_INT32_TWO
#define IPV6_ADDR_INT32_TWO 2
#endif
#ifndef IPV6_ADDR_INT32_MNL
#define IPV6_ADDR_INT32_MNL 0xff010000
#endif
#ifndef IPV6_ADDR_INT32_MLL
#define IPV6_ADDR_INT32_MLL 0xff020000
#endif
#ifndef IPV6_ADDR_INT32_SMP
#define IPV6_ADDR_INT32_SMP 0x0000ffff
#endif
#ifndef IPV6_ADDR_INT16_ULL
#define IPV6_ADDR_INT16_ULL 0xfe80
#endif
#ifndef IPV6_ADDR_INT16_USL
#define IPV6_ADDR_INT16_USL 0xfec0
#endif
#ifndef IPV6_ADDR_INT16_MLL
#define IPV6_ADDR_INT16_MLL 0xff02
#endif
#ifndef IPV6_ADDR_INT32_ONE
#define IPV6_ADDR_INT32_ONE 0x01000000
#endif
#ifndef IPV6_ADDR_INT32_TWO
#define IPV6_ADDR_INT32_TWO 0x02000000
#endif
#ifndef IPV6_ADDR_INT32_MNL
#define IPV6_ADDR_INT32_MNL 0x000001ff
#endif
#ifndef IPV6_ADDR_INT32_MLL
#define IPV6_ADDR_INT32_MLL 0x000002ff
#endif
#ifndef IPV6_ADDR_INT32_SMP
#define IPV6_ADDR_INT32_SMP 0xffff0000
#endif
#ifndef IPV6_ADDR_INT16_ULL
#define IPV6_ADDR_INT16_ULL 0x80fe
#endif
#ifndef IPV6_ADDR_INT16_USL
#define IPV6_ADDR_INT16_USL 0xc0fe
#endif
#ifndef IPV6_ADDR_INT16_MLL
#define IPV6_ADDR_INT16_MLL 0x02ff
#endif
#ifndef IPV6_ADDR_SCOPE_NODELOCAL
#define IPV6_ADDR_SCOPE_NODELOCAL 0x01
#endif
#ifndef IPV6_ADDR_SCOPE_INTFACELOCAL
#define IPV6_ADDR_SCOPE_INTFACELOCAL 0x01
#endif
#ifndef IPV6_ADDR_SCOPE_LINKLOCAL
#define IPV6_ADDR_SCOPE_LINKLOCAL 0x02
#endif
#ifndef IPV6_ADDR_SCOPE_SITELOCAL
#define IPV6_ADDR_SCOPE_SITELOCAL 0x05
#endif
#ifndef IPV6_ADDR_SCOPE_ORGLOCAL
#define IPV6_ADDR_SCOPE_ORGLOCAL 0x08 /* just used in this file */
#endif
#ifndef IPV6_ADDR_SCOPE_GLOBAL
#define IPV6_ADDR_SCOPE_GLOBAL 0x0e
#endif
#ifndef IPV6_OPTIONS
#define IPV6_OPTIONS 1 /* buf/ip6_opts; set/get IP6 options */
#endif
#ifndef IPV6_RECVOPTS
#define IPV6_RECVOPTS 5 /* bool; receive all IP6 opts w/dgram */
#endif
#ifndef IPV6_RECVRETOPTS
#define IPV6_RECVRETOPTS 6 /* bool; receive IP6 opts for response */
#endif
#ifndef IPV6_RECVDSTADDR
#define IPV6_RECVDSTADDR 7 /* bool; receive IP6 dst addr w/dgram */
#endif
#ifndef IPV6_RETOPTS
#define IPV6_RETOPTS 8 /* ip6_opts; set/get IP6 options */
#endif
#ifndef IPV6_SOCKOPT_RESERVED1
#define IPV6_SOCKOPT_RESERVED1 3 /* reserved for future use */
#endif
#ifndef IPV6_UNICAST_HOPS
#define IPV6_UNICAST_HOPS 4 /* int; IP6 hops */
#endif
#ifndef IPV6_MULTICAST_IF
#define IPV6_MULTICAST_IF 9 /* __uint8_t; set/get IP6 multicast i/f */
#endif
#ifndef IPV6_MULTICAST_HOPS
#define IPV6_MULTICAST_HOPS 10 /* __uint8_t; set/get IP6 multicast hops */
#endif
#ifndef IPV6_MULTICAST_LOOP
#define IPV6_MULTICAST_LOOP 11 /* __uint8_t; set/get IP6 mcast loopback */
#endif
#ifndef IPV6_JOIN_GROUP
#define IPV6_JOIN_GROUP 12 /* ip6_mreq; join a group membership */
#endif
#ifndef IPV6_LEAVE_GROUP
#define IPV6_LEAVE_GROUP 13 /* ip6_mreq; leave a group membership */
#endif
#ifndef IPV6_PORTRANGE
#define IPV6_PORTRANGE 14 /* int; range to choose for unspec port */
#endif
#ifndef IPV6_2292PKTINFO
#define IPV6_2292PKTINFO 19 /* bool; send/recv if, src/dst addr */
#endif
#ifndef IPV6_2292HOPLIMIT
#define IPV6_2292HOPLIMIT 20 /* bool; hop limit */
#endif
#ifndef IPV6_2292NEXTHOP
#define IPV6_2292NEXTHOP 21 /* bool; next hop addr */
#endif
#ifndef IPV6_2292HOPOPTS
#define IPV6_2292HOPOPTS 22 /* bool; hop-by-hop option */
#endif
#ifndef IPV6_2292DSTOPTS
#define IPV6_2292DSTOPTS 23 /* bool; destinaion option */
#endif
#ifndef IPV6_2292RTHDR
#define IPV6_2292RTHDR 24 /* ip6_rthdr: routing header */
#endif
#ifndef IPV6_2292PKTOPTIONS
#define IPV6_2292PKTOPTIONS 25
#endif
#ifndef IPV6_CHECKSUM
#define IPV6_CHECKSUM 26 /* int; checksum offset for raw socket */
#endif
#ifndef IPV6_V6ONLY
#define IPV6_V6ONLY 27 /* bool; only bind INET6 at wildcard bind */
#endif
#ifndef IPV6_IPSEC_POLICY
#define IPV6_IPSEC_POLICY 28 /* struct; get/set security policy */
#endif
#ifndef IPV6_FAITH
#define IPV6_FAITH 29 /* deprecated */
#endif
#ifndef IPV6_FW_ADD
#define IPV6_FW_ADD 30 /* add a firewall rule to chain */
#endif
#ifndef IPV6_FW_DEL
#define IPV6_FW_DEL 31 /* delete a firewall rule from chain */
#endif
#ifndef IPV6_FW_FLUSH
#define IPV6_FW_FLUSH 32 /* flush firewall rule chain */
#endif
#ifndef IPV6_FW_ZERO
#define IPV6_FW_ZERO 33 /* clear single/all firewall counter(s) */
#endif
#ifndef IPV6_FW_GET
#define IPV6_FW_GET 34 /* get entire firewall rule chain */
#endif
#ifndef IPV6_RECVTCLASS
#define IPV6_RECVTCLASS 35 /* bool; recv traffic class values */
#endif
#ifndef IPV6_TCLASS
#define IPV6_TCLASS 36 /* int; send traffic class value */
#endif
#ifndef IPV6_RTHDRDSTOPTS
#define IPV6_RTHDRDSTOPTS 57
#endif
#ifndef IPV6_RECVPKTINFO
#define IPV6_RECVPKTINFO 61
#endif
#ifndef IPV6_RECVHOPLIMIT
#define IPV6_RECVHOPLIMIT 37 /* bool; recv hop limit */
#endif
#ifndef IPV6_RECVRTHDR
#define IPV6_RECVRTHDR 38 /* bool; recv routing header */
#endif
#ifndef IPV6_RECVHOPOPTS
#define IPV6_RECVHOPOPTS 39 /* bool; recv hop-by-hop option */
#endif
#ifndef IPV6_RECVDSTOPTS
#define IPV6_RECVDSTOPTS 40 /* bool; recv dst option after rthdr */
#endif
#ifndef IPV6_RECVRTHDRDSTOPTS
#define IPV6_RECVRTHDRDSTOPTS 41 /* bool; recv dst option before rthdr */
#endif
#ifndef IPV6_USE_MIN_MTU
#define IPV6_USE_MIN_MTU 42 /* bool; send packets at the minimum MTU */
#endif
#ifndef IPV6_RECVPATHMTU
#define IPV6_RECVPATHMTU 43 /* bool; notify an according MTU */
#endif
#ifndef IPV6_PATHMTU
#define IPV6_PATHMTU 44
#endif
#ifndef IPV6_REACHCONF
#define IPV6_REACHCONF 45
#endif
#ifndef IPV6_3542PKTINFO
#define IPV6_3542PKTINFO 46 /* in6_pktinfo; send if, src addr */
#endif
#ifndef IPV6_3542HOPLIMIT
#define IPV6_3542HOPLIMIT 47 /* int; send hop limit */
#endif
#ifndef IPV6_3542NEXTHOP
#define IPV6_3542NEXTHOP 48 /* sockaddr; next hop addr */
#endif
#ifndef IPV6_3542HOPOPTS
#define IPV6_3542HOPOPTS 49 /* ip6_hbh; send hop-by-hop option */
#endif
#ifndef IPV6_3542DSTOPTS
#define IPV6_3542DSTOPTS 50 /* ip6_dest; send dst option befor rthdr */
#endif
#ifndef IPV6_3542RTHDR
#define IPV6_3542RTHDR 51 /* ip6_rthdr; send routing header */
#endif
#ifndef IPV6_AUTOFLOWLABEL
#define IPV6_AUTOFLOWLABEL 59 /* bool; attach flowlabel automagically */
#endif
#ifndef IPV6_DONTFRAG
#define IPV6_DONTFRAG 62 /* bool; disable IPv6 fragmentation */
#endif
#ifndef IPV6_PREFER_TEMPADDR
#define IPV6_PREFER_TEMPADDR 63
#endif
#ifndef IPV6_MSFILTER
#define IPV6_MSFILTER 74 /* struct __msfilterreq; */
#endif
#ifndef IPV6_BOUND_IF
#define IPV6_BOUND_IF 125 /* int; set/get bound interface */
#endif
#ifndef IPV6_NO_IFT_CELLULAR
#define IPV6_NO_IFT_CELLULAR 6969 /* for internal use only */
#endif
#ifndef IPV6_OUT_IF
#define IPV6_OUT_IF 9696 /* for internal use only */
#endif
#ifndef IPV6_RTHDR_LOOSE
#define IPV6_RTHDR_LOOSE 0 /* this hop need not be a neighbor. */
#endif
#ifndef IPV6_RTHDR_STRICT
#define IPV6_RTHDR_STRICT 1 /* this hop must be a neighbor. */
#endif
#ifndef IPV6_RTHDR_TYPE_0
#define IPV6_RTHDR_TYPE_0 0 /* IPv6 routing header type 0 */
#endif
#ifndef IPV6_DEFAULT_MULTICAST_HOPS
#define IPV6_DEFAULT_MULTICAST_HOPS 1 /* normally limit m'casts to 1 hop */
#endif
#ifndef IPV6_DEFAULT_MULTICAST_LOOP
#define IPV6_DEFAULT_MULTICAST_LOOP 1 /* normally hear sends if a member */
#endif
#ifndef IPV6_MIN_MEMBERSHIPS
#define IPV6_MIN_MEMBERSHIPS 31
#endif
#ifndef IPV6_MAX_MEMBERSHIPS
#define IPV6_MAX_MEMBERSHIPS 4095
#endif
#ifndef IPV6_MAX_GROUP_SRC_FILTER
#define IPV6_MAX_GROUP_SRC_FILTER 512 /* sources per group */
#endif
#ifndef IPV6_MAX_SOCK_SRC_FILTER
#define IPV6_MAX_SOCK_SRC_FILTER 128 /* sources per socket/group */
#endif
#ifndef IPV6_PORTRANGE_DEFAULT
#define IPV6_PORTRANGE_DEFAULT 0 /* default range */
#endif
#ifndef IPV6_PORTRANGE_HIGH
#define IPV6_PORTRANGE_HIGH 1 /* "high" - request firewall bypass */
#endif
#ifndef IPV6_PORTRANGE_LOW
#define IPV6_PORTRANGE_LOW 2 /* "low" - vouchsafe security */
#endif

/* XNU spells the RFC 3542 option names as aliases of the 2292 numbers
 * (these are macros, not plain values, so the numeric sweep above does
 * not pick them up); libnetutil uses the RFC names. */
#ifndef IPV6_HOPOPTS
#define IPV6_HOPOPTS	IPV6_2292HOPOPTS
#endif
#ifndef IPV6_RTHDR
#define IPV6_RTHDR	IPV6_2292RTHDR
#endif
#ifndef IPV6_DSTOPTS
#define IPV6_DSTOPTS	IPV6_2292DSTOPTS
#endif
