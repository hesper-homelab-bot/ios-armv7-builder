#ifndef _LIBPROC_H_
#define _LIBPROC_H_
/*
 * libproc.h for cross-compiling against iOS 10.3 (armv7).
 *
 * The proc_* structures and PROC_* flavor constants now come from
 * sys/proc_info.h, which is a verbatim copy of the header from the
 * device's exact kernel (xnu-3789.70.16).  Earlier revisions of this
 * header hand-declared a few of them; that is how PROC_PIDTBSDINFO got
 * published as 4 (the kernel's value is 3) -- a layout mismatch waiting
 * for a caller.  Only the function declarations live here now.
 *
 * iOS exports the proc_* functions from libSystem (verified on the
 * device via proc_pidinfo; proc_pidfdinfo/proc_pidfileportinfo are the
 * same libproc family and are exercised by lsof 4.99.x).
 */

#include <sys/types.h>
#include <sys/proc_info.h>
#include <Availability.h>

#ifndef MAXCOMLEN
#define MAXCOMLEN 16
#endif
#ifndef MAXPATHLEN
#define MAXPATHLEN 1024
#endif

int	proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer,
		int buffersize);
int	proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer,
		int buffersize);
int	proc_pidfdinfo(int pid, int fd, int flavor, void *buffer,
		int buffersize);
int	proc_pidfileportinfo(int pid, uint32_t fileport, int flavor,
		void *buffer, int buffersize);
int	proc_pidpath(int pid, void *buffer, uint32_t buffersize);
int	proc_name(int pid, void *buffer, uint32_t buffersize);

#endif
