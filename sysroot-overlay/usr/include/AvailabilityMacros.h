/*
 * Target availability for the cross sysroot.
 *
 * MAC_OS_X_VERSION_MIN_REQUIRED is a *macOS SDK* concept: the real iOS SDK
 * does not define it at all.  We used to define it as 1080 so that
 * configure scripts and tmux would pick the libproc (proc_pidinfo) code
 * paths instead of the sysctl(KERN_PROC) ones -- libproc is what this
 * sysroot implements.
 *
 * Defining it unconditionally backfired on c-ares, whose Apple config code
 * reads `MAC_OS_X_VERSION_MIN_REQUIRED >= 1080` to select the
 * SystemConfiguration-based DNS configuration path -- a platform framework,
 * and one that cannot even be linked here: the device kernel kills any
 * binary whose LC_LOAD_DYLIB references a platform framework (verified with
 * a tbd-linked probe, 2026-11-07).
 *
 * The macro is therefore scoped: it stays defined for the C/C++ code that
 * uses it as an availability hint, but a translation unit that wants the
 * strict Apple semantics can set IOS_STRICT_APPLE_AVAILABILITY to make the
 * header behave like the iOS SDK (no MAC_OS_X_VERSION_* at all).
 */
#ifndef __AVAILABILITYMACROS_H__
#define __AVAILABILITYMACROS_H__

#include <Availability.h>

#ifndef IOS_STRICT_APPLE_AVAILABILITY
#ifndef MAC_OS_X_VERSION_MIN_REQUIRED
#define MAC_OS_X_VERSION_MIN_REQUIRED 1080
#endif
#ifndef MAC_OS_X_VERSION_MAX_ALLOWED
#define MAC_OS_X_VERSION_MAX_ALLOWED 1080
#endif
#endif /* !IOS_STRICT_APPLE_AVAILABILITY */

#endif
