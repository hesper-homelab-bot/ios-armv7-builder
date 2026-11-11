#ifndef _CRT_EXTERNS_H_
#define _CRT_EXTERNS_H_

/*
 * Minimal Darwin crt_externs.h for the iOS armv7 cross build.
 *
 * _NSGetEnviron() is exported by libSystem (verified against the device);
 * code on Darwin must not read the `environ` symbol directly, it fetches
 * the environment vector through this call.
 */

#include <stdint.h>

char ***_NSGetEnviron(void);

/*
 * _NSGetExecutablePath() fills buf with the path of the running
 * executable and updates *bufsize to the length used.  Note the return
 * type: it is char *, not int -- the call returns the buffer on success
 * and NULL on failure, which is easy to get wrong because the
 * documentation phrases it as "returns 0 on success".
 *
 * Verified on device (2026-11-08): with a 4096-byte buffer the call
 * returned NULL, i.e. it takes the failure path for an already-resolved
 * path in this configuration.  The char* signature is what the device's
 * libSystem actually implements; declaring int here produced an
 * "incompatible pointer to integer conversion" error in a probe.
 *
 * libuv uses it (uv_exepath) to report the current process image.
 */
char *_NSGetExecutablePath(char *buf, uint32_t *bufsize);

#endif /* _CRT_EXTERNS_H_ */
