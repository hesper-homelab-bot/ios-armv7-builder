#ifndef _SYS_UN_H
#define _SYS_UN_H

/*
 * Darwin sockaddr_un for the iOS armv7 cross build.  musl's version has
 * no sun_len, which shifts sun_path and breaks any struct that crosses
 * the kernel ABI (e.g. un_sockinfo in sys/proc_info.h).
 *
 * Field layout verified against xnu-3789.70.16 bsd/sys/un.h.
 */

#include <sys/socket.h>

struct sockaddr_un {
	unsigned char	sun_len;	/* sockaddr len including null */
	sa_family_t	sun_family;	/* AF_UNIX */
	char		sun_path[104];	/* path name (gag) */
};

/* Level number of get/setsockopt for local domain sockets */
#define SOL_LOCAL		0

/* Socket options. */
#define LOCAL_PEERCRED		0x001
#define LOCAL_PEERPID		0x002
#define LOCAL_PEEREPID		0x003
#define LOCAL_PEERUUID		0x004
#define LOCAL_PEEREUUID		0x005

#endif

/* BSD macro (4.3BSD/netns, also in Darwin's sys/un.h): length of a
 * sockaddr_un that only fills sun_path up to its NUL.  Pure arithmetic
 * on the caller's struct; libdnet/nmap call it. */
#ifndef SUN_LEN
#define SUN_LEN(ptr) ((sizeof(*(ptr)) - sizeof((ptr)->sun_path))	\
		      + strlen((ptr)->sun_path))
#endif
