#ifndef _MACH_MACH_H_
#define _MACH_MACH_H_

/*
 * Aggregator <mach/mach.h> for the iOS armv7 cross build.  Foundation's
 * mach.h pulls in dozens of kernel-interface headers; only the pieces
 * cross-built userspace actually names are provided here.  All of the
 * functions are exported by libSystem on iOS (verified on device while
 * porting lsof: task_threads/vm_deallocate through mach_task_self_).
 */

#include <mach/machine.h>
#include <mach/boolean.h>
#include <mach/port.h>
#include <mach/message.h>
#include <mach/clock_types.h>
#include <mach/mach_init.h>
#include <mach/mach_time.h>
#include <mach/thread_info.h>
#include <mach/thread_act.h>
#include <mach/task.h>
#include <mach/host_info.h>
#include <mach/semaphore.h>
#include <mach/vm_map.h>
#include <mach/vm_statistics.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>

#endif
