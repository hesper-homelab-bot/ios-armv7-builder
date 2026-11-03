#ifndef _NETINET_IN_H
#define _NETINET_IN_H

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

struct sockaddr_in {
    sa_family_t sin_family;
    in_port_t sin_port;
    struct in_addr sin_addr;
    char sin_zero[8];
};

#define IPV6_JOIN_GROUP     12
#define IPV6_LEAVE_GROUP    13
#define IPV6_MULTICAST_HOPS 18
#define IPV6_MULTICAST_IF   17
#define IPV6_MULTICAST_LOOP 19
#define IPV6_UNICAST_HOPS   16
#define IPV6_V6ONLY         26

#define IPV6_CHECKSUM       7
#define IPV6_DONTFRAG       62
#define IPV6_HOPLIMIT       21
#define IPV6_HOPOPTS        0
#define IPV6_NEXTHOP        10
#define IPV6_PATHMTU        11
#define IPV6_PKTINFO        12
#define IPV6_RECVDSTOPTS    9
#define IPV6_RECVHOPLIMIT   10
#define IPV6_RECVHOPOPTS    8
#define IPV6_RECVPKTINFO    11
#define IPV6_RECVRTHDR      13
#define IPV6_RECVTCLASS     14
#define IPV6_RTHDR          15
#define IPV6_RTHDRDSTOPTS   16
#define IPV6_RTHDRTYPE      17
#define IPV6_RECVRTHDR      13
#define IPV6_TCLASS         14
#define IPV6_UNICAST_HOPS   16

#define IPV6_RTHDR_LOOSE    0
#define IPV6_RTHDR_STRICT   1

#define INADDR_ANY          ((in_addr_t)0x00000000)
#define INADDR_BROADCAST    ((in_addr_t)0xffffffff)
#define INADDR_LOOPBACK     0x7f000001
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

#endif
