/*
 * src-compat.c — iOS 10.3.3 cross-build shims for gnulib stragglers.
 * (2026-11-20, hand-link port; see build.sh for the full story)
 *
 * gl_msvc_inval_ensure_handler: gnulib's MSVC invalid-parameter hook; the
 *   constant-true probe defined MSVC machinery on a POSIX target, and
 *   close.o/fstat.o/raise.o reference the ensure-handler. On POSIX the
 *   handler does nothing — provide the external definition the header's
 *   non-inline path expects.
 * rpl_write: gnulib's lib/unistd.h redirects write() when REPLACE_WRITE is
 *   (falsely) set, but lib/write.c compiles to nothing on POSIX. Route
 *   straight to the real write(2).
 */
#include <stddef.h>
#include <unistd.h>

void gl_msvc_inval_ensure_handler (void) { }

ssize_t
rpl_write (int fd, const void *buf, size_t n)
{
  return write (fd, buf, n);
}
