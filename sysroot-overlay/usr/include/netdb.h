#ifndef _NETDB_H
#define _NETDB_H

#include <features.h>
#include <sys/socket.h>
#include <netinet/in.h>

#define __NEED_socklen_t
#define __NEED_size_t
#include <bits/alltypes.h>

struct addrinfo {
	int	ai_flags;
	int	ai_family;
	int	ai_socktype;
	int	ai_protocol;
	socklen_t ai_addrlen;
	char	*ai_canonname;	/* Darwin order: canonname before addr */
	struct sockaddr *ai_addr;
	struct addrinfo *ai_next;
};



struct hostent {
    char *h_name;
    char **h_aliases;
    int h_addrtype;
    int h_length;
    char **h_addr_list;
};

#define h_addr h_addr_list[0]

struct netent {
    char *n_name;
    char **n_aliases;
    int n_addrtype;
    unsigned long n_net;
};

struct servent {
    char *s_name;
    char **s_aliases;
    int s_port;
    char *s_proto;
};

struct protoent {
    char *p_name;
    char **p_aliases;
    int p_proto;
};

#ifdef __cplusplus
extern "C" {
#endif
int sethostent(int);
int setnetent(int);
int setprotoent(int);
int setservent(int);
void endhostent(void);
void endnetent(void);
void endprotoent(void);
void endservent(void);
struct hostent *gethostbyaddr(const void *, socklen_t, int);
struct hostent *gethostbyname(const char *);
struct hostent *gethostbyname2(const char *, int);
struct hostent *gethostent(void);
struct netent *getnetbyaddr(uint32_t, int);
struct netent *getnetbyname(const char *);
struct netent *getnetent(void);
struct protoent *getprotobyname(const char *);
struct protoent *getprotobynumber(int);
struct protoent *getprotoent(void);
struct servent *getservbyname(const char *, const char *);
struct servent *getservbyport(int, const char *);
struct servent *getservent(void);

void freeaddrinfo(struct addrinfo *);
int getaddrinfo(const char *__restrict, const char *__restrict,
    const struct addrinfo *__restrict, struct addrinfo **__restrict);
const char *gai_strerror(int);
int getnameinfo(const struct sockaddr *__restrict, socklen_t,
    char *__restrict, socklen_t, char *__restrict, socklen_t, int);


#define HOST_NOT_FOUND 1
#define TRY_AGAIN      2
#define NO_RECOVERY    3
#define NO_DATA        4
#define NO_ADDRESS     NO_DATA

int sethostent(int);
int setnetent(int);
int setprotoent(int);
int setservent(int);
void endhostent(void);
void endnetent(void);
void endprotoent(void);
void endservent(void);


/* Darwin: h_errno is a plain global in libSystem (legacy resolver API).
   Guarded so a threading layer can still override it with a macro.
   NOTE: kept inside the extern "C" block -- libpcap's pcap/socket.h
   includes this header inside its own extern "C", and a bare
   declaration outside would flip h_errno's linkage between the two
   inclusion contexts (C++: declaration of 'h_errno' has a different
   language linkage). */
#if !defined(h_errno)
extern int h_errno;
#endif

#ifdef __cplusplus
}
#endif

#endif

/* ---- getaddrinfo/getnameinfo constants: APPLE/Darwin values, NOT the
 * glibc/musl ones musl ships.  Probe-verified on the device (2026-11-12):
 * NI_NUMERICHOST=1 returns the HOSTNAME (it is NI_NOFQDN on Darwin), =2
 * returns the numeric address; a non-numeric string with AI_NUMERICHOST
 * fails with rc=8 = EAI_NONAME here, while musl spells EAI_NONAME -2.
 * Source of record: apple-oss-distributions/Libinfo lookup.subproj/netdb.h. ---- */

#define EAI_ADDRFAMILY  1
#define EAI_AGAIN       2
#define EAI_BADFLAGS    3
#define EAI_FAIL        4
#define EAI_FAMILY      5
#define EAI_MEMORY      6
#define EAI_NODATA      7
#define EAI_NONAME      8
#define EAI_SERVICE     9
#define EAI_SOCKTYPE    10
#define EAI_SYSTEM      11
#define EAI_BADHINTS    12
#define EAI_PROTOCOL    13
#define EAI_OVERFLOW    14
#define EAI_MAX         15

#define NI_NOFQDN       0x00000001
#define NI_NUMERICHOST  0x00000002
#define NI_NAMEREQD     0x00000004
#define NI_NUMERICSERV  0x00000008
#define NI_DGRAM        0x00000010
#define NI_WITHSCOPEID  0x00000020

#define AI_PASSIVE      0x00000001
#define AI_CANONNAME    0x00000002
#define AI_NUMERICHOST  0x00000004
#define AI_ALL          0x00000100
#define AI_V4MAPPED_CFG 0x00000200
#define AI_ADDRCONFIG   0x00000400
#define AI_V4MAPPED     0x00000800
#define AI_NUMERICSERV  0x00001000
#define AI_UNUSABLE     0x10000000

/* Apple keeps the buffer sizes here too (Libinfo netdb.h). */
#define NI_MAXHOST 1025
#define NI_MAXSERV 32
