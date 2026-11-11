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
/* boolean_t is the Mach spelling of C's int boolean; xnu defines it in
 * osfmk/mach/boolean.h, which re-exports it through <mach/machine.h> on
 * Apple platforms.  It was missing from the whole sysroot while
 * sys/proc_info.h already used it -- adding it here fixes both. */
typedef int		boolean_t;
typedef int		cpu_type_t;
typedef int		cpu_subtype_t;
typedef int		cpu_threadtype_t;

#endif
