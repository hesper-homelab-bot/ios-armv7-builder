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
