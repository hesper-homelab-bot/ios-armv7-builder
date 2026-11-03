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
