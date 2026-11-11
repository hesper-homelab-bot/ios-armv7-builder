#ifndef _OS_AVAILABILITY_H_MINIMAL_
#define _OS_AVAILABILITY_H_MINIMAL_

/*
 * Minimal <os/availability.h> for the iOS armv7 cross build.  On Apple
 * platforms this is the SDK forwarding layer onto <Availability.h>; the
 * sysroot has the latter already.  Everything here is a compiler
 * annotation that the armv7 clang accepts and that changes no code -- the
 * point is only that headers written against the SDK (libdispatch's
 * dispatch/*.h among them) parse.
 */

#include <Availability.h>

#ifndef API_AVAILABLE
#define API_AVAILABLE(...)
#endif
#ifndef API_DEPRECATED
#define API_DEPRECATED(...)
#endif
#ifndef API_DEPRECATED_WITH_REPLACEMENT
#define API_DEPRECATED_WITH_REPLACEMENT(...)
#endif
#ifndef API_UNAVAILABLE
#define API_UNAVAILABLE(...)
#endif
#ifndef API_UNAVAILABLE_BEGIN
#define API_UNAVAILABLE_BEGIN(...)
#endif
#ifndef API_UNAVAILABLE_END
#define API_UNAVAILABLE_END
#endif

/* Swift spellings, also annotation-only. */
#ifndef __API_AVAILABLE
#define __API_AVAILABLE(...)
#endif
#ifndef __API_DEPRECATED
#define __API_DEPRECATED(...)
#endif
#ifndef __API_DEPRECATED_WITH_REPLACEMENT
#define __API_DEPRECATED_WITH_REPLACEMENT(...)
#endif
#ifndef __API_UNAVAILABLE
#define __API_UNAVAILABLE(...)
#endif

/* The C++-style variants libdispatch's headers use. */
#ifndef __OSX_AVAILABLE_STARTING
#define __OSX_AVAILABLE_STARTING(...)
#endif
#ifndef __OSX_AVAILABLE_BUT_DEPRECATED
#define __OSX_AVAILABLE_BUT_DEPRECATED(...)
#endif

#endif
