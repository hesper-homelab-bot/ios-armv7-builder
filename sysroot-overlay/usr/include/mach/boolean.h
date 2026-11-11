#ifndef _MACH_BOOLEAN_H_
#define _MACH_BOOLEAN_H_

/*
 * <mach/boolean.h> for the iOS armv7 cross build.  xnu spells the Mach
 * boolean as int (osfmk/mach/boolean.h: typedef int boolean_t) and both
 * TRUE/FALSE are the Mach variants, kept distinct from C99's bool on
 * purpose so that code can rely on the 4-byte width.
 */

#include <mach/machine.h>

#ifndef TRUE
#define TRUE	1
#endif
#ifndef FALSE
#define FALSE	0
#endif

#endif
