#ifndef _PTHREAD_H_IOS_OVERLAY
#define _PTHREAD_H_IOS_OVERLAY

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Darwin (iOS 10, 32-bit armv7) pthread types and declarations.
 *
 * Replaces musl's pthread.h wholesale: musl's pthread_once_t is a 4-byte
 * int and PTHREAD_ONCE_INIT is 0, while Darwin's pthread_once_t is a
 * 12-byte {long __sig; char __opaque[8];} whose __sig must be
 * _PTHREAD_ONCE_SIG_init (0x71B7236C) before pthread_once may be called.
 * Passing musl-sized objects made every static once/mutex/cond corrupt
 * adjacent memory and aborted inside os_once
 * ("Unlock of an os_once_t not owned by current thread").
 *
 * Sizes and signatures are the !__LP64__ branch of Darwin's
 * sys/_pthread/_pthread_types.h.
 */
#ifndef _PTHREAD_H
#define _PTHREAD_H

#include <sys/types.h>
#include <pthread/qos.h>   /* QoS classes; the SDK pulls these in implicitly */
#include <time.h>

#define __PTHREAD_ONCE_SIZE__		8
#define __PTHREAD_MUTEX_SIZE__		40
#define __PTHREAD_COND_SIZE__		24
#define __PTHREAD_RWLOCK_SIZE__		124
#define __PTHREAD_ATTR_SIZE__		36
#define __PTHREAD_MUTEXATTR_SIZE__	8
#define __PTHREAD_CONDATTR_SIZE__	4
#define __PTHREAD_RWLOCKATTR_SIZE__	16

#define _PTHREAD_ONCE_SIG_init		0x71B7236C
#define _PTHREAD_MUTEX_SIG_init		0x32AAABA7
#define _PTHREAD_COND_SIG_init		0x3CB0B1BB
#define _PTHREAD_RWLOCK_SIG_init	0x2FA8BEAA

typedef struct _opaque_pthread_once_t {
	long	__sig;
	char	__opaque[__PTHREAD_ONCE_SIZE__];
} pthread_once_t;

typedef struct _opaque_pthread_mutex_t {
	long	__sig;
	char	__opaque[__PTHREAD_MUTEX_SIZE__];
} pthread_mutex_t;

typedef struct _opaque_pthread_cond_t {
	long	__sig;
	char	__opaque[__PTHREAD_COND_SIZE__];
} pthread_cond_t;

typedef struct _opaque_pthread_rwlock_t {
	long	__sig;
	char	__opaque[__PTHREAD_RWLOCK_SIZE__];
} pthread_rwlock_t;

typedef struct _opaque_pthread_attr_t {
	long	__sig;
	char	__opaque[__PTHREAD_ATTR_SIZE__];
} pthread_attr_t;

typedef struct _opaque_pthread_mutexattr_t {
	long	__sig;
	char	__opaque[__PTHREAD_MUTEXATTR_SIZE__];
} pthread_mutexattr_t;

typedef struct _opaque_pthread_condattr_t {
	long	__sig;
	char	__opaque[__PTHREAD_CONDATTR_SIZE__];
} pthread_condattr_t;

typedef struct _opaque_pthread_rwlockattr_t {
	long	__sig;
	char	__opaque[__PTHREAD_RWLOCKATTR_SIZE__];
} pthread_rwlockattr_t;

typedef unsigned long pthread_key_t;	/* Darwin: unsigned long */
typedef struct _opaque_pthread_t *pthread_t;

#define PTHREAD_ONCE_INIT		{_PTHREAD_ONCE_SIG_init, {0,0,0,0}}
#define PTHREAD_MUTEX_INITIALIZER	{_PTHREAD_MUTEX_SIG_init, {0,0,0,0,0,0,0,0,0,0}}
#define PTHREAD_COND_INITIALIZER	{_PTHREAD_COND_SIG_init, {0,0,0,0,0,0}}
#define PTHREAD_RWLOCK_INITIALIZER	{_PTHREAD_RWLOCK_SIG_init, {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}}

/* Darwin constants (note: DETACHED=2 differs from Linux!) */
#define PTHREAD_CREATE_JOINABLE		1
#define PTHREAD_CREATE_DETACHED		2
#define PTHREAD_INHERIT_SCHED		1
#define PTHREAD_EXPLICIT_SCHED		2
#define PTHREAD_CANCEL_ENABLE		0x01
#define PTHREAD_CANCEL_DISABLE		0x02
#define PTHREAD_CANCEL_DEFERRED		0
#define PTHREAD_CANCELED		((void *)-1)
#define PTHREAD_MUTEX_NORMAL		0
#define PTHREAD_MUTEX_ERRORCHECK	1
#define PTHREAD_MUTEX_RECURSIVE		2
#define PTHREAD_MUTEX_DEFAULT		PTHREAD_MUTEX_NORMAL
#define PTHREAD_PROCESS_PRIVATE		0
#define PTHREAD_PROCESS_SHARED		1

/* ---- threads ---- */
int	pthread_create(pthread_t *__restrict, const pthread_attr_t *__restrict,
	    void *(*)(void *), void *__restrict);
int	pthread_join(pthread_t, void **);
int	pthread_detach(pthread_t);
pthread_t pthread_self(void);
int	pthread_equal(pthread_t, pthread_t);
void	pthread_exit(void *);
int	pthread_cancel(pthread_t);

int	pthread_once(pthread_once_t *, void (*)(void));

/* ---- mutex ---- */
int	pthread_mutex_init(pthread_mutex_t *__restrict,
	    const pthread_mutexattr_t *__restrict);
int	pthread_mutex_destroy(pthread_mutex_t *);
int	pthread_mutex_lock(pthread_mutex_t *);
int	pthread_mutex_trylock(pthread_mutex_t *);
int	pthread_mutex_unlock(pthread_mutex_t *);
int	pthread_mutexattr_init(pthread_mutexattr_t *);
int	pthread_mutexattr_destroy(pthread_mutexattr_t *);
int	pthread_mutexattr_settype(pthread_mutexattr_t *, int);
int	pthread_mutexattr_gettype(const pthread_mutexattr_t *, int *);

/* ---- condition variables ---- */
int	pthread_cond_init(pthread_cond_t *__restrict,
	    const pthread_condattr_t *__restrict);
int	pthread_cond_destroy(pthread_cond_t *);
int	pthread_cond_wait(pthread_cond_t *__restrict,
	    pthread_mutex_t *__restrict);
int	pthread_cond_timedwait(pthread_cond_t *__restrict,
	    pthread_mutex_t *__restrict, const struct timespec *__restrict);
int	pthread_cond_signal(pthread_cond_t *);
int	pthread_cond_broadcast(pthread_cond_t *);
int	pthread_condattr_init(pthread_condattr_t *);
int	pthread_condattr_destroy(pthread_condattr_t *);

/* ---- rwlock ---- */
int	pthread_rwlock_init(pthread_rwlock_t *__restrict,
	    const pthread_rwlockattr_t *__restrict);
int	pthread_rwlock_destroy(pthread_rwlock_t *);
int	pthread_rwlock_rdlock(pthread_rwlock_t *);
int	pthread_rwlock_tryrdlock(pthread_rwlock_t *);
int	pthread_rwlock_wrlock(pthread_rwlock_t *);
int	pthread_rwlock_trywrlock(pthread_rwlock_t *);
int	pthread_rwlock_unlock(pthread_rwlock_t *);
int	pthread_rwlockattr_init(pthread_rwlockattr_t *);
int	pthread_rwlockattr_destroy(pthread_rwlockattr_t *);

/* ---- thread-local storage ---- */
int	pthread_key_create(pthread_key_t *, void (*)(void *));
int	pthread_key_delete(pthread_key_t);
void   *pthread_getspecific(pthread_key_t);
int	pthread_setspecific(pthread_key_t, const void *);

/* ---- cancellation ---- */
int	pthread_setcancelstate(int, int *);
int	pthread_setcanceltype(int, int *);
void	pthread_testcancel(void);

/* ---- attributes ---- */
int	pthread_attr_init(pthread_attr_t *);
int	pthread_attr_destroy(pthread_attr_t *);
int	pthread_attr_setdetachstate(pthread_attr_t *, int);
int	pthread_attr_getdetachstate(const pthread_attr_t *, int *);
int	pthread_attr_setstacksize(pthread_attr_t *, size_t);
int	pthread_attr_getstacksize(const pthread_attr_t *, size_t *);

#endif

/*
 * pthread_threadid_np -- Darwin's global unique thread id (not the pthread
 * handle).  Present in libSystem; verified on device 2026-11-07 (probe
 * returned a plausible tid, rc=0).  V8/abseil sysinfo uses it.
 */
int	pthread_threadid_np(pthread_t, unsigned long long *);

/* Darwin extensions used by abseil (verified on device 2026-11-07: both
 * resolve from libSystem; the probe segfaulted only because it passed
 * NULL cond/mutex to the relative wait, which dereferences them). */
struct sched_param;
int	pthread_cond_timedwait_relative_np(pthread_cond_t *,
	    pthread_mutex_t *, const struct timespec *);
int	pthread_getschedparam(pthread_t, int *, struct sched_param *);
int	pthread_setschedparam(pthread_t, int, const struct sched_param *);

/* Darwin _np introspection.  pthread_get_stackaddr_np and
 * mach_port_deallocate were both verified on device (2026-11-07). */
/* Standard POSIX fork handlers.  This header replaces musl's wholesale,
 * so every standard entry point has to be re-declared; pthread_atfork was
 * missed until c-ares hit it.  Verified on device: returns 0. */
int	pthread_atfork(void (*prepare)(void), void (*parent)(void),
	    void (*child)(void));

void *	pthread_get_stackaddr_np(pthread_t);
size_t	pthread_get_stacksize_np(pthread_t);
int	pthread_jit_write_protect_np(int);

/*
 * Thread naming.  The Darwin signatures are NOT the Linux ones:
 *
 *     Darwin: int pthread_setname_np(const char *name);
 *     Linux:  int pthread_setname_np(pthread_t, const char *name);
 *
 * libuv calls the one-argument form on Darwin
 * (thread.c: pthread_setname_np(namebuf)), so the Linux spelling would
 * silently select the wrong overload.
 *
 * Verified on device (2026-11-08): pthread_setname_np("probe") returned 0.
 */
int	pthread_getname_np(pthread_t, char *, size_t);
int	pthread_setname_np(const char *);

#ifdef __cplusplus
}
#endif
#endif /* _PTHREAD_H_IOS_OVERLAY */
