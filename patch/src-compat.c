/*
 * src-compat.c — iOS 10.3.3 cross-build shims for gnulib stragglers.
 * gl_msvc_inval_ensure_handler: MSVC-only hook referenced by close/fstat/
 *   raise replacements (constant-true probe defined MSVC machinery); no-op
 *   on POSIX.
 * rpl_write: gnulib's generated unistd.h redirects write() when
 *   REPLACE_WRITE is (falsely) set, but lib/write.c compiles to nothing on
 *   POSIX — route straight to the real write(2).
 */
#include <stddef.h>
#include <unistd.h>

void gl_msvc_inval_ensure_handler (void) { }

ssize_t
rpl_write (int fd, const void *buf, size_t n)
{
  return write (fd, buf, n);
}
