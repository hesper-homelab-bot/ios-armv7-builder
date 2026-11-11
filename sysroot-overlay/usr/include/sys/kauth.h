#ifndef _SYS_KAUTH_H_
#define _SYS_KAUTH_H_

/*
 * Minimal <sys/kauth.h> for the iOS armv7 cross build.
 *
 * Apple's real header is 794 lines of kernel-authorisation API and it is
 * not something user space can call; libuv includes it from
 * src/unix/process.c purely as a Darwin habit and references none of its
 * symbols (checked across the whole file, 2026-11-08 -- the include is the
 * only mention).  A compatibility shell is therefore the honest thing to
 * provide rather than a transcription of a kernel interface.
 *
 * The two constants below are the only user-space-visible ones, and their
 * values are taken from xnu-3789.70.16 bsd/sys/kauth.h (lines 50-51):
 *
 *     #define KAUTH_UID_NONE  (~(uid_t)0 - 100)
 *     #define KAUTH_GID_NONE  (~(gid_t)0 - 100)
 *
 * i.e. "a uid/gid that cannot be valid", used as a sentinel by callers
 * that want to distinguish "no owner" from uid 0.
 */

#include <sys/types.h>

#ifndef KAUTH_UID_NONE
#define KAUTH_UID_NONE	(~(uid_t)0 - 100)
#endif
#ifndef KAUTH_GID_NONE
#define KAUTH_GID_NONE	(~(gid_t)0 - 100)
#endif

#endif /* _SYS_KAUTH_H_ */
