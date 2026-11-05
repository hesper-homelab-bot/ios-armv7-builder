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
    sa_family_t sin6_family;
    in_port_t sin6_port;
    uint32_t sin6_flowinfo;
    struct in6_addr sin6_addr;
    uint32_t sin6_scope_id;
};

#define IN6ADDR_ANY_INIT { { { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 } } }
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
     (**(const uint32_t *)((const char *)(a)+4) == 0) && \
     (*(const uint32_t *)((const char *)(a)+8) == 0) && \
     (*(const uint32_t *)((const char *)(a)+12) == ntohl(1)))

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
