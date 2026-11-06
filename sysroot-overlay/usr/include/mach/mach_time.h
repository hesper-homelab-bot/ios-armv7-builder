#ifndef _MACH_MACH_TIME_H_
#define _MACH_MACH_TIME_H_

/*
 * Clean-room stub for <mach/mach_time.h>, continuing the pattern of mach/mach.h
 * above.
 *
 * Apple deleted the Mach timing declarations from the standalone header years
 * ago and folded them into <mach/mach.h>, so the standalone name is not
 * something musl (or anything derived from it) will ever provide.  iOS 10
 * exports both functions regardless.
 *
 * Dropbear's dbutil.c needs them for its monotonic clock when
 * HAVE_MACH_ABSOLUTE_TIME is set, and configure does set it -- it probes for
 * the mach/mach_time.h header separately, so a normal autoconf run picks up
 * the function while the header is absent and the build dies with
 *
 *     error: unknown type name 'mach_timebase_info_data_t'
 *     error: call to undeclared function 'mach_timebase_info'
 *
 * Verified on the device (iPad 4, iOS 10.3.3): calling both returns
 * mach_absolute_time = 2201214266670 with numer = 125, denom = 3.
 *
 * Layout matters and is easy to get backwards: on Darwin the two fields are
 * unsigned 32-bit values packed together, not pointers or 64-bit words.
 */
#include <stdint.h>

typedef struct {
	uint32_t	numer;
	uint32_t	denom;
} mach_timebase_info_data_t;

typedef mach_timebase_info_data_t mach_timebase_info_data_t;

int   mach_timebase_info(mach_timebase_info_data_t *info);
uint64_t mach_absolute_time(void);

#endif /* _MACH_MACH_TIME_H_ */
