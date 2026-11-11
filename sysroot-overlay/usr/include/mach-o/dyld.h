#ifndef _MACH_O_DYLD_H_
#define _MACH_O_DYLD_H_

/*
 * <mach-o/dyld.h> for the iOS armv7 cross build.  Only the image-iteration
 * entry points V8's platform-darwin.cc uses (to report loaded libraries);
 * all four are exported by libSystem.
 *
 * Verified on device (iPad 4, iOS 10.3.3, 2026-11-07): image_count = 39,
 * image_name(0) = the running binary's path, vmaddr_slide(0) = 442368.
 */

#include <stdint.h>
#include <mach-o/loader.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t	_dyld_image_count(void);
const struct mach_header *_dyld_get_image_header(uint32_t image_index);
intptr_t	_dyld_get_image_vmaddr_slide(uint32_t image_index);
const char *	_dyld_get_image_name(uint32_t image_index);

/*
 * _NSGetExecutablePath belongs to <crt_externs.h> in Apple's SDK, but
 * libuv includes only <mach-o/dyld.h> for it -- its include line even
 * carries the comment "/* _NSGetExecutablePath" -- and the real SDK gets
 * away with that because crt_externs.h arrives through other headers.
 * Declaring it here too costs nothing (the guard keeps a single
 * definition) and makes the obvious include sufficient.
 *
 * The return type is char *, not int: the call yields the buffer on
 * success and NULL on failure.  Verified on device, 2026-11-08.
 */
#ifndef _NSGETEXECUTABLEPATH_DECLARED
#define _NSGETEXECUTABLEPATH_DECLARED
char *_NSGetExecutablePath(char *buf, uint32_t *bufsize);
#endif

#ifdef __cplusplus
}
#endif

#endif
