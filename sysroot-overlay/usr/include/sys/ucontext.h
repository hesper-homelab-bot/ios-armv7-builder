#ifndef _SYS_UCONTEXT_H_
#define _SYS_UCONTEXT_H_

/* Darwin delegates <sys/ucontext.h> to <ucontext.h>; musl did the same.
 * The real (Darwin armv7) definition lives in ../ucontext.h. */
#include <ucontext.h>

#endif
