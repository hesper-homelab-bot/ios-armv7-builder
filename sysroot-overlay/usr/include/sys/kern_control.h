#ifndef _SYS_KERN_CONTROL_H
#define _SYS_KERN_CONTROL_H

/*
 * Minimal Darwin sys/kern_control.h for the iOS armv7 cross build --
 * sys/proc_info.h includes it for struct sockaddr_ctl, which is embedded
 * in kern_ctl_info.  Values verified against xnu-3789.70.16.
 */

#include <sys/types.h>
#include <sys/socket.h>

#define MAX_KCTL_NAME	96

struct sockaddr_ctl {
	unsigned char	sc_len;		/* depends on size of bundle ID string */
	unsigned char	sc_family;	/* AF_SYSTEM */
	uint16_t	ss_sysaddr;	/* AF_SYS_KERNCONTROL */
	uint32_t	sc_id;		/* controller unique identifier */
	uint32_t	sc_unit;	/* developer private unit number */
	uint32_t	sc_reserved[5];
};

#endif
