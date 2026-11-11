#ifndef _MACH_MACH_TIME_H_
#define _MACH_MACH_TIME_H_


#ifdef __cplusplus
extern "C" {
#endif

/*
 * <mach/mach_time.h> for the iOS armv7 cross build.
 *
 * Note the name collision that trips builds: on Darwin `mach_timebase_info`
 * is BOTH a struct tag and a function.  Code written against the SDK says
 *
 *     mach_timebase_info_data_t info;
 *     mach_timebase_info(&info);
 *
 * which only compiles if the struct is named `mach_timebase_info` and the
 * function of the same name exists.  Verified on device (iPad 4, iOS 10.3.3):
 * mach_absolute_time() = 2201214266670, numer=125, denom=3 -- so 24 MHz.
 */

#include <stdint.h>

struct mach_timebase_info {
	uint32_t	numer;
	uint32_t	denom;
};
typedef struct mach_timebase_info mach_timebase_info_data_t;

int		mach_timebase_info(mach_timebase_info_data_t *info);
uint64_t	mach_absolute_time(void);

/*
 * mach_continuous_time() keeps counting across system sleep, unlike
 * mach_absolute_time().  Verified on device (2026-11-08): returned
 * 3500032722238 -- nanoseconds since boot.
 */
uint64_t	mach_continuous_time(void);
uint64_t	mach_approximate_time(void);


#ifdef __cplusplus
}
#endif

#endif
