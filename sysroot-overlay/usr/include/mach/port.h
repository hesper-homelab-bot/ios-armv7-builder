#ifndef _MACH_PORT_H_
#define _MACH_PORT_H_

/*
 * Minimal mach/port.h for the iOS armv7 cross build.  lsof's darwin
 * dialect machine.h embeds a mach_port_t in struct lfile and needs
 * MACH_PORT_NULL.
 *
 * Verified against xnu-3789.70.16 osfmk/mach/port.h: in user space
 * mach_port_t is mach_port_name_t, which is natural_t (unsigned int),
 * and MACH_PORT_NULL is 0.
 */

typedef unsigned int	natural_t;
typedef natural_t	mach_port_name_t;
typedef mach_port_name_t mach_port_t;

#define MACH_PORT_NULL		0
#define MACH_PORT_DEAD		((mach_port_t)-1)

#endif
