#ifndef _SCHED_H_IOS_OVERLAY
#define _SCHED_H_IOS_OVERLAY


#ifdef __cplusplus
extern "C" {
#endif

/*
 * Minimal <sched.h> for the iOS armv7 cross build.
 *
 * The sysroot is musl-derived and musl's <sched.h> lives behind feature
 * macros this overlay does not enable, so the pieces cross-built code
 * actually names are spelled out here.
 *
 * Verified on device (iPad 4, iOS 10.3.3, 2026-11-07):
 *   sched_get_priority_max(0) = 47
 *   sched_get_priority_min(0) = 15
 * which is Darwin's real range (SCHED_FIFO/RR sit at 15..47; SCHED_OTHER
 * has no adjustable priority).
 */

#include <sys/types.h>

struct sched_param {
	int	sched_priority;
};

int	sched_yield(void);
int	sched_get_priority_max(int);
int	sched_get_priority_min(int);
int	sched_setscheduler(pid_t, int, const struct sched_param *);
int	sched_getscheduler(pid_t);

/* Darwin's policy numbers differ from Linux's: 1 is FIFO and 2 is RR on
 * Darwin (Linux has FIFO=1, RR=2 as well, but also a distinct OTHER=0;
 * all three agree here for the values used by callers). */
#define SCHED_OTHER	0
#define SCHED_FIFO	4
#define SCHED_RR	2


#ifdef __cplusplus
}
#endif

#endif
