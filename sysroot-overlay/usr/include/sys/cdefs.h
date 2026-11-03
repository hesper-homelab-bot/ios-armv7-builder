/*
 * Minimal sys/cdefs.h for the cross sysroot.
 *
 * Darwin's headers (and tmux >= 3.8's osdep-darwin.c) include this for the
 * BSD compiler macros.  clang provides the underlying __attribute__s; these
 * are just the traditional spellings.
 */
#ifndef _SYS_CDEFS_H_
#define _SYS_CDEFS_H_

#define __BEGIN_DECLS
#define __END_DECLS

#ifndef __unused
#define __unused	__attribute__((unused))
#endif
#ifndef __used
#define __used		__attribute__((used))
#endif
#ifndef __packed
#define __packed	__attribute__((packed))
#endif
#ifndef __dead
#define __dead		__attribute__((noreturn))
#endif
#ifndef __pure
#define __pure		__attribute__((const))
#endif
#ifndef __printflike
#define __printflike(fmtarg, firstvararg) \
	__attribute__((__format__(__printf__, fmtarg, firstvararg)))
#endif
#ifndef __scanflike
#define __scanflike(fmtarg, firstvararg) \
	__attribute__((__format__(__scanf__, fmtarg, firstvararg)))
#endif
#ifndef __weak_symbol
#define __weak_symbol	__attribute__((weak))
#endif
#ifndef __predict_true
#define __predict_true(exp)	__builtin_expect(!!(exp), 1)
#endif
#ifndef __predict_false
#define __predict_false(exp)	__builtin_expect(!!(exp), 0)
#endif

#endif
