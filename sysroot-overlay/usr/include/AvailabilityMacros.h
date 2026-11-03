/*
 * Target availability for the cross sysroot.
 *
 * Claim a modern macOS version so configure/tmux pick the proc_pidinfo()
 * code paths (libproc) instead of the sysctl(KERN_PROC) ones - libproc is
 * what the stub libproc.h implements, and sys/sysctl.h is not provided.
 */
#ifndef __AVAILABILITYMACROS_H__
#define __AVAILABILITYMACROS_H__

#include <Availability.h>

#ifndef MAC_OS_X_VERSION_MIN_REQUIRED
#define MAC_OS_X_VERSION_MIN_REQUIRED 1080
#endif
#ifndef MAC_OS_X_VERSION_MAX_ALLOWED
#define MAC_OS_X_VERSION_MAX_ALLOWED 1080
#endif

#endif
