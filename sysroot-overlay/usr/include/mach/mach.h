#ifndef _MACH_MACH_H_
#define _MACH_MACH_H_
/* Minimal mach/mach.h stub: enough for tmux's compat/daemon-darwin.c */
#include <sys/types.h>

typedef unsigned int mach_port_t;
typedef int          kern_return_t;
typedef unsigned int mach_msg_type_number_t;

#define MACH_PORT_NULL  0
#define KERN_SUCCESS    0
#define KERN_FAILURE    5

extern mach_port_t mach_task_self_;
#define mach_task_self() mach_task_self_
extern mach_port_t bootstrap_port;

kern_return_t mach_port_deallocate(mach_port_t, mach_port_t);
kern_return_t task_set_bootstrap_port(mach_port_t, mach_port_t);

#endif
