#ifndef _MACH_THREAD_INFO_H_
#define _MACH_THREAD_INFO_H_

/*
 * Minimal mach/thread_info.h for the iOS armv7 cross build: the basic
 * per-thread accounting V8's base/platform/time.cc reads through
 * task_info().  Layout from xnu-3789.70.16 osfmk/mach/thread_info.h.
 */

#include <mach/machine.h>
#include <mach/message.h>
#include <mach/port.h>

typedef int		policy_t;
typedef integer_t	*thread_info_t;
typedef natural_t	thread_info_data_t;

/*
 * vm_size_t is natural_t on this ABI.  It is defined in mach/vm_map.h,
 * which this header cannot include (vm_map.h pulls in the whole VM
 * interface); task_basic_info below needs it, so it is spelled out here
 * behind a guard that keeps the two definitions from colliding.
 */
#ifndef VM_SIZE_T_DEFINED
#define VM_SIZE_T_DEFINED
typedef natural_t	vm_size_t;
#endif

struct time_value {
	integer_t seconds;
	integer_t microseconds;
};
typedef struct time_value	time_value_t;

struct thread_basic_info {
	time_value_t	user_time;	/* user run time */
	time_value_t	system_time;	/* system run time */
	integer_t	cpu_usage;	/* scaled cpu usage percentage */
	policy_t	policy;		/* scheduling policy in effect */
	integer_t	run_state;	/* run state */
	integer_t	flags;		/* various flags */
	integer_t	suspend_count;	/* suspend count for thread */
	integer_t	sleep_time;	/* seconds thread has slept */
};
typedef struct thread_basic_info	thread_basic_info_data_t;
typedef struct thread_basic_info *	thread_basic_info_t;

#define THREAD_BASIC_INFO		3
#define THREAD_BASIC_INFO_COUNT \
	((mach_msg_type_number_t)(sizeof(thread_basic_info_data_t) / sizeof(natural_t)))

/*
 * task_info() flavours.  libuv reads TASK_BASIC_INFO for resident memory
 * (uv_resident_set_memory); V8 reads THREAD_BASIC_INFO for per-thread CPU
 * time.  Layouts from xnu-3789.70.16 osfmk/mach/task_info.h.
 *
 * TASK_BASIC_INFO_COUNT is derived from the struct rather than hardcoded:
 * an earlier draft used a literal 10, which is the count on some
 * architectures but silently truncates the struct here.
 */
#define TASK_BASIC_INFO			4
#define TASK_BASIC_INFO_64		5
#define TASK_THREAD_TIMES_INFO		3

struct task_basic_info {
	integer_t	suspend_count;	/* suspend count for task */
	vm_size_t	virtual_size;	/* virtual memory size (bytes) */
	vm_size_t	resident_size;	/* resident memory size (bytes) */
	time_value_t	user_time;	/* total user run time */
	time_value_t	system_time;	/* total system run time */
	policy_t	policy;		/* default policy for new threads */
};
typedef struct task_basic_info		task_basic_info_data_t;
typedef struct task_basic_info *	task_basic_info_t;

#define TASK_BASIC_INFO_COUNT \
	((mach_msg_type_number_t)(sizeof(task_basic_info_data_t) / sizeof(natural_t)))

#endif
