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

#define AI_PASSIVE     0x0001
#define AI_CANONNAME   0x0002
#define AI_NUMERICHOST 0x0004
#define AI_V4MAPPED    0x0008
#define AI_ALL         0x0010
#define AI_ADDRCONFIG  0x0020
#define AI_NUMERICSERV 0x0400

#define EAI_BADFLAGS   -1
#define EAI_NONAME     -2
#define EAI_AGAIN      -3
#define EAI_FAIL       -4
#define EAI_NODATA     -5
#define EAI_FAMILY     -6
#define EAI_SOCKTYPE   -7
#define EAI_SERVICE    -8
#define EAI_MEMORY     -10
#define EAI_SYSTEM     -11
#define EAI_OVERFLOW   -12

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

#define NI_NUMERICHOST 1
#define NI_NUMERICSERV 2
#define NI_NOFQDN      4
#define NI_NAMEREQD    8
#define NI_DGRAM       16
#define NI_MAXHOST     1025
#define NI_MAXSERV     32

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

#ifdef __cplusplus
}
#endif

#endif
