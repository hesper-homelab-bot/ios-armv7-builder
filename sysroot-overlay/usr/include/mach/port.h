#ifndef _MACH_PORT_H_
#define _MACH_PORT_H_


#ifdef __cplusplus
extern "C" {
#endif

/*
 * Minimal mach/port.h for the iOS armv7 cross build.  lsof's darwin
 * dialect machine.h embeds a mach_port_t in struct lfile and needs
 * MACH_PORT_NULL.
 *
 * Verified against xnu-3789.70.16 osfmk/mach/port.h: in user space
 * mach_port_t is mach_port_name_t, which is natural_t (unsigned int),
 * and MACH_PORT_NULL is 0.
 */

/* kern_return_t belongs to mach/kern_return.h, which mach_init.h pulls in;
 * port.h is included BY mach_init.h, so the scalar is defined here to keep
 * the header self-contained.  xnu: typedef int kern_return_t. */
typedef int		kern_return_t;

typedef unsigned int	natural_t;
typedef natural_t	mach_port_name_t;
typedef mach_port_name_t mach_port_t;

#define MACH_PORT_NULL		0
#define MACH_PORT_DEAD		((mach_port_t)-1)

/* Port right management.  mach_port_deallocate verified on device
 * (returned KERN_SUCCESS); the rest are the same MIG family. */
kern_return_t	mach_port_deallocate(mach_port_t, mach_port_t);
kern_return_t	mach_port_mod_refs(mach_port_t, mach_port_t, int, int);


#ifdef __cplusplus
}
#endif

#endif
