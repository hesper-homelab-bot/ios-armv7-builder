#ifndef _OS_BASE_H_MINIMAL_
#define _OS_BASE_H_MINIMAL_

/*
 * Minimal <os/base.h> for the iOS armv7 cross build.  On Apple platforms
 * this is an SDK header carrying compiler-annotation macros.  Only the
 * spellings libdispatch/Swift-corelibs headers actually reference are
 * defined here; the semantics are the standard Apple ones (visibility,
 * availability and Objective-C independence).
 */

#include <os/availability.h>

#ifndef OS_EXPORT
#define OS_EXPORT __attribute__((visibility("default")))
#endif
#ifndef OS_NOINLINE
#define OS_NOINLINE __attribute__((noinline))
#endif
#ifndef OS_ALWAYS_INLINE
#define OS_ALWAYS_INLINE __attribute__((always_inline)) inline
#endif
#ifndef OS_OBJC_INDEPENDENT_CLASS
#define OS_OBJC_INDEPENDENT_CLASS __attribute__((objc_independent_class))
#endif
#ifndef OS_SWIFT_UNAVAILABLE
#define OS_SWIFT_UNAVAILABLE(...)
#endif
#ifndef OS_SWIFT_NAME
#define OS_SWIFT_NAME(...)
#endif

#endif
