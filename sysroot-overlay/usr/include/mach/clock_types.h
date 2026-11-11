#ifndef _MACH_CLOCK_TYPES_H_
#define _MACH_CLOCK_TYPES_H_

/*
 * Minimal mach/clock_types.h for the iOS armv7 cross build.  libdispatch's
 * <dispatch/time.h> includes it for mach_timespec_t.  Layout from
 * xnu-3789.70.16 osfmk/mach/clock_types.h.
 */

#include <mach/machine.h>

typedef int		clock_res_t;
typedef unsigned int	clock_id_t;
typedef int		clock_flavor_t;
typedef int *		clock_attr_t;

struct mach_timespec {
	unsigned int	tv_sec;
	clock_res_t	tv_nsec;
};
typedef struct mach_timespec	mach_timespec_t;

#define TIME_ABSOLUTE	0x00
#define TIME_RELATIVE	0x01

#endif
