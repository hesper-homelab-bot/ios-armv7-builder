#include <features.h>

#undef assert

#ifdef NDEBUG
#define	assert(x) (void)0
#else
/* iOS libSystem does not export musl's __assert_fail.  It does export the
 * Darwin __assert_rtn(func, file, line, expr), probe-verified live on an
 * iPad 4 (2026-11-12): it prints "Assertion failed: (expr), function func,
 * file file.c, line 42." and aborts.  Note the argument order differs from
 * __assert_fail: the function name comes FIRST. */
#define assert(x) ((void)((x) || (__assert_rtn(__func__, __FILE__, __LINE__, #x),0)))
#endif

#if __STDC_VERSION__ >= 201112L && !defined(__cplusplus)
#define static_assert _Static_assert
#endif

#ifdef __cplusplus
extern "C" {
#endif

extern void __assert_rtn (const char *, const char *, int, const char *) __attribute__((__noreturn__));

#ifdef __cplusplus
}
#endif
