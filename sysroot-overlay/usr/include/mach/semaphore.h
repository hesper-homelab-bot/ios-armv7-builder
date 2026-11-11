#ifndef _MACH_SEMAPHORE_H_
#define _MACH_SEMAPHORE_H_

/*
 * <mach/semaphore.h> for the iOS armv7 cross build.
 *
 * This is the low-level Mach semaphore (a kernel port), distinct from
 * POSIX sem_t and from dispatch_semaphore_t.  V8 only includes the header,
 * but libuv's thread.c actually calls semaphore_create/signal/destroy for
 * uv_sem_t on Darwin, which is why the entry points are declared here.
 *
 * Verified on device (iPad 4, iOS 10.3.3, 2026-11-08):
 *   semaphore_create(mach_task_self_, &sem, SYNC_POLICY_FIFO, 0) -> 0,
 *   producing a live port (2819 in the probe); semaphore_signal() and
 *   semaphore_destroy() then succeeded as well.
 */

#include <mach/mach_init.h>
#include <mach/machine.h>

typedef mach_port_t	semaphore_t;

/* sync policies (Darwin sync_policy_t) */
#define SYNC_POLICY_FIFO		0
#define SYNC_POLICY_FIXED_PRIORITY	1
#define SYNC_POLICY_REVERSED		2
#define SYNC_POLICY_ORDER_MASK		7
#define SYNC_POLICY_LIFO		(SYNC_POLICY_FIFO | SYNC_POLICY_REVERSED)

kern_return_t	semaphore_create(task_t task, semaphore_t *semaphore,
		    int policy, int value);
kern_return_t	semaphore_destroy(task_t task, semaphore_t semaphore);
kern_return_t	semaphore_signal(semaphore_t semaphore);
kern_return_t	semaphore_signal_all(semaphore_t semaphore);
kern_return_t	semaphore_wait(semaphore_t semaphore);
kern_return_t	semaphore_timedwait(semaphore_t semaphore,
		    mach_timespec_t wait_time);
kern_return_t	semaphore_timedwait_signal(semaphore_t wait_semaphore,
		    semaphore_t signal_semaphore, mach_timespec_t wait_time);

#endif
