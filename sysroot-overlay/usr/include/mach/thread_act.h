#ifndef _MACH_THREAD_ACT_H_
#define _MACH_THREAD_ACT_H_


#ifdef __cplusplus
extern "C" {
#endif

/*
 * Minimal mach/thread_act.h for the iOS armv7 cross build: the thread-port
 * lookup V8 uses for per-thread CPU accounting.  pthread_mach_thread_np()
 * and task_threads() are both exported by libSystem on iOS.
 */

#include <mach/mach_init.h>
#include <mach/thread_info.h>
#include <pthread.h>

typedef mach_port_t	task_t;
typedef mach_port_t	thread_t;
typedef thread_t *	thread_array_t;
typedef integer_t *	task_info_t;

thread_t	pthread_mach_thread_np(pthread_t);
kern_return_t	thread_info(thread_t, int, thread_info_t,
		    mach_msg_type_number_t *);
kern_return_t	task_info(task_t, int, task_info_t, mach_msg_type_number_t *);


#ifdef __cplusplus
}
#endif

#endif
