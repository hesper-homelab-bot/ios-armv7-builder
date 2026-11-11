#ifndef _UCONTEXT_H
#define _UCONTEXT_H

/*
 * Darwin armv7 <ucontext.h> for the iOS cross build.
 *
 * This replaces musl's, which is opaque (a forward-declared struct with no
 * members) and whose <signal.h> transitively defines __ucontext with a
 * Linux-style sigcontext.  Neither can express the Darwin arm32 mcontext
 * that signal handlers are handed, so V8's sampler (and anything else that
 * reads registers out of a ucontext) could not compile.
 *
 * Layout: the arm 32-bit _STRUCT_MCONTEXT --
 *
 *     _STRUCT_MCONTEXT {
 *         _STRUCT_ARM_EXCEPTION_STATE __es;   // 12 bytes: trap/fsr/far
 *         _STRUCT_ARM_THREAD_STATE    __ss;   // 64 bytes: __r[0..15]
 *         _STRUCT_ARM_VFP_STATE       __fs;
 *     }
 *
 * so __ss begins at offset 12, __r[13] (sp) lands at 64, r[14] (lr) at 68
 * and r[15] (pc) at 72.
 *
 * VALIDATED ON DEVICE (iPad 4, iOS 10.3.3, 2026-11-08): a probe installed a
 * SIGUSR2 handler, raised the signal, and read the registers out of the
 * ucontext passed to it.  r[15] held an address in the probe's own text,
 * r[13] a stack address, and r[11] a plausible frame pointer -- the offsets
 * are measured, not reconstructed.
 */

#ifdef __cplusplus
extern "C" {
#endif

#include <features.h>
#include <signal.h>

#ifndef _IOS_ARM_STRUCT_MCONTEXT_DEFINED
#define _IOS_ARM_STRUCT_MCONTEXT_DEFINED

typedef struct _STRUCT_ARM_EXCEPTION_STATE {
	__uint32_t	__trap;
	__uint32_t	__fsr;
	__uint32_t	__far;
} _STRUCT_ARM_EXCEPTION_STATE;

typedef struct _STRUCT_ARM_THREAD_STATE {
	__uint32_t	__r[16];
} _STRUCT_ARM_THREAD_STATE;

/* Only what the armv7 kernel saves; nothing here reads the VFP block. */
typedef struct _STRUCT_ARM_VFP_STATE {
	__uint32_t	__r[64];
} _STRUCT_ARM_VFP_STATE;

typedef struct _STRUCT_MCONTEXT {
	_STRUCT_ARM_EXCEPTION_STATE __es;
	_STRUCT_ARM_THREAD_STATE __ss;
	_STRUCT_ARM_VFP_STATE __fs;
} _STRUCT_MCONTEXT;

#endif /* _IOS_ARM_STRUCT_MCONTEXT_DEFINED */

/* Darwin spells mcontext_t as a POINTER to the context block (Linux keeps it
 * by value), which is why upstream's iOS sampler code can write
 * mcontext->__ss.__pc on a reference bound to uc_mcontext. */
typedef struct _STRUCT_MCONTEXT *mcontext_t;

typedef struct __ucontext ucontext_t;

struct __ucontext {
	int		uc_onstack;
	int		uc_link;
	sigset_t	uc_sigmask;
	stack_t		uc_stack;
	mcontext_t	uc_mcontext;
	/* Darwin's ucontext_t ends with padding; the exact type is unimportant
	 * (nothing reads it) and using the musl pid_t would need the whole
	 * __NEED_* dance from <sys/types.h>.  Four bytes is what the kernel
	 * lays out here regardless. */
	int		uc_pad[7];
};

int	getcontext(ucontext_t *);
void	makecontext(ucontext_t *, void (*)(void), int, ...);
int	setcontext(const ucontext_t *);
int	swapcontext(ucontext_t *, const ucontext_t *);

#ifdef __cplusplus
}
#endif

#endif /* _UCONTEXT_H */
