#ifndef _MACH_MACHINE_H_
#define _MACH_MACHINE_H_

/*
 * Minimal mach/machine.h for the iOS armv7 cross build.  sys/proc_info.h
 * includes it for cpu_type_t / cpu_subtype_t (struct proc_archinfo).
 *
 * Verified against xnu-3789.70.16 osfmk/mach/machine.h:
 *     typedef integer_t cpu_type_t;
 * and integer_t is int on this ABI.
 */

typedef int		integer_t;
typedef int		cpu_type_t;
typedef int		cpu_subtype_t;
typedef int		cpu_threadtype_t;

#endif
