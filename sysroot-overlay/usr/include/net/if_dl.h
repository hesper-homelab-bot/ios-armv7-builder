#ifndef _NET_IF_DL_H_
#define _NET_IF_DL_H_

/*
 * Minimal Darwin net/if_dl.h for the iOS armv7 cross build: sockaddr_dl
 * as returned by getifaddrs() for AF_LINK addresses (libuv's
 * bsd-ifaddrs.c).  Field-for-field from xnu-3789.70.16 bsd/net/if_dl.h.
 */

#include <sys/types.h>
#include <sys/socket.h>

struct sockaddr_dl {
	unsigned char	sdl_len;	/* total length of sockaddr */
	sa_family_t	sdl_family;	/* AF_LINK */
	unsigned short	sdl_index;	/* system given index for interface */
	unsigned char	sdl_type;	/* interface type */
	unsigned char	sdl_nlen;	/* interface name length */
	unsigned char	sdl_alen;	/* link level address length */
	unsigned char	sdl_slen;	/* link layer selector length */
	char		sdl_data[12];	/* contains both if name and ll address */
};

#define LLADDR(s)	((char *)((s)->sdl_data + (s)->sdl_nlen))

#endif
