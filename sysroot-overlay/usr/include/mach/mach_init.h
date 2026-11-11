#ifndef _MACH_MACH_INIT_H_
#define _MACH_MACH_INIT_H_

/*
 * Minimal mach/mach_init.h for the iOS armv7 cross build.
 * kern_return_t is int on this ABI (xnu osfmk/mach/kern_return.h:
 * typedef int kern_return_t).  mach_task_self_ is exported by libSystem
 * and equals 1 (the task's own port); verified on device by a probe that
 * calls task_threads() through it.
 */

#include <mach/port.h>

typedef int		kern_return_t;
typedef natural_t	mach_msg_type_number_t;

/*
 * kern_return_t values, from xnu-3789.70.16 osfmk/mach/kern_return.h.
 * The base two were here first; libuv's semaphore and thread paths needed
 * the rest (it compares against KERN_ABORTED and propagates the others).
 */
#define KERN_SUCCESS			0
#define KERN_INVALID_ADDRESS		1
#define KERN_PROTECTION_FAILURE		2
#define KERN_NO_SPACE			3
#define KERN_INVALID_ARGUMENT		4
#define KERN_FAILURE			5
#define KERN_RESOURCE_SHORTAGE		6
#define KERN_NOT_RECEIVER		7
#define KERN_NO_ACCESS			8
#define KERN_MEMORY_FAILURE		9
#define KERN_MEMORY_ERROR		10
#define KERN_ABORTED			14
#define KERN_INVALID_NAME		15
#define KERN_INVALID_TASK		16
#define KERN_INVALID_RIGHT		17
#define KERN_INVALID_VALUE		18
#define KERN_NOT_SUPPORTED		46
#define KERN_OPERATION_TIMED_OUT	49

extern mach_port_t	mach_task_self_;
/* Verified on device: returns a live thread port (1027 on the probe). */
mach_port_t	mach_thread_self(void);
#define mach_task_self()	mach_task_self_
#define mach_port_self()	mach_task_self()

/*
 * vm_map_t is the task's address-space port.  This typedef used to sit
 * *after* the include guard's #endif, i.e. outside the header entirely,
 * so it was never actually defined for any consumer -- mach/vm_map.h's
 * declarations of vm_deallocate/vm_allocate silently relied on an
 * implicit type.  Kept here, before the guard ends.
 */
typedef mach_port_t		vm_map_t;

#endif /* _MACH_MACH_INIT_H_ */
