#ifndef _EXECINFO_H
#define _EXECINFO_H


#ifdef __cplusplus
extern "C" {
#endif

/*
 * Minimal Darwin execinfo.h for the iOS armv7 cross build: the classic
 * BSD backtrace interface, exported by libSystem (verified on device:
 * a probe captured 8 frames and resolved names through backtrace_symbols,
 * 2026-11-07).  Consumer: abseil's stacktrace/symbolize.
 */

#include <sys/cdefs.h>

__BEGIN_DECLS

int	backtrace(void **, int);
char **	backtrace_symbols(void *const *, int);
void	backtrace_symbols_fd(void *const *, int, int);

__END_DECLS


#ifdef __cplusplus
}
#endif

#endif
