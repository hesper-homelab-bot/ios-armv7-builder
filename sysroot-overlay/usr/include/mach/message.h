#ifndef _MACH_MESSAGE_H_
#define _MACH_MESSAGE_H_

/*
 * Minimal mach/message.h for the iOS armv7 cross build: only the message
 * scalar types libdispatch's public headers name.  The full message
 * structs are kernel/IPC ABI and are deliberately absent -- nothing in the
 * sysroot sends Mach messages.
 */

#include <mach/port.h>
#include <mach/clock_types.h>

typedef unsigned int	mach_msg_bits_t;
typedef unsigned int	mach_msg_size_t;
typedef unsigned int	mach_msg_id_t;
typedef int		mach_msg_option_t;
typedef int		mach_msg_return_t;
typedef unsigned int	mach_msg_timeout_t;
typedef unsigned int	mach_msg_priority_t;

#define MACH_MSG_TIMEOUT_NONE	0
#define MACH_PORT_NULL		0

#endif
