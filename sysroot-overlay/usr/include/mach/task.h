#ifndef _MACH_TASK_H_
#define _MACH_TASK_H_

/*
 * Minimal mach/task.h for the iOS armv7 cross build: just what gtest's
 * GetThreadCount() needs.  task_threads() is exported by libSystem.
 */

#include <mach/mach_init.h>

typedef mach_port_t		task_t;
typedef mach_port_t		thread_act_t;
typedef thread_act_t		*thread_act_array_t;
typedef mach_port_t		thread_t;

kern_return_t	task_threads(task_t task, thread_act_array_t *threads,
		    mach_msg_type_number_t *count);

#endif
