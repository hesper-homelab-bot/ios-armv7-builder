/*
 * spawn.h -- Darwin-ABI <spawn.h> for the armv7 iOS sysroot.
 *
 * musl's <spawn.h> describes the *Linux* posix_spawn ABI, where both opaque
 * types are fat by-value structs:
 *
 *     posix_spawnattr_t          int __flags; pid_t __pgrp; sigset_t x2;
 *                                int __prio, __pol; void *__fn; char pad[...]
 *                                -> 80 bytes on armv7
 *     posix_spawn_file_actions_t int __pad0[2]; void *__actions; int __pad[16]
 *                                -> 72 bytes on armv7
 *
 * Darwin uses the classic pre-POSIX.1-2008 representation instead: each of
 * them is a single pointer to a heap object allocated by its _init function.
 *
 * Measured on the device (iPad 4, iOS 10.3.3) by calling the real
 * posix_spawnattr_init() on a buffer pre-filled with 0xAA:
 *
 *     attr_init rc=0 first8: 20 84 52 16 aa aa aa aa
 *     fa_init   rc=0 first8: 00 84 9c 16 aa aa aa aa
 *
 * Only the first four bytes are written -- a pointer -- and the remaining
 * bytes still hold 0xAA.  So both types are 4 bytes wide here, not 80/72.
 *
 * Getting this wrong is silent: the caller reserves 80 bytes, the callee
 * uses the first 4, and any code that reads back a field at musl's offset
 * (or copies the struct) reads garbage.
 *
 * This header keeps musl's prototypes and the POSIX constants (they match)
 * but redefines the two types to what the device's libSystem actually
 * expects.  No Apple header is copied; the layout was derived from the
 * observed behaviour of the device's own libSystem.
 */
#ifndef _IOS_SPAWN_H
#define _IOS_SPAWN_H

#ifdef __cplusplus
extern "C" {
#endif

#include <features.h>

#define __NEED_mode_t
#define __NEED_pid_t
#define __NEED_sigset_t

#include <bits/alltypes.h>

struct sched_param;

/* POSIX.1-2001 (and Darwin) flag values. */
#define POSIX_SPAWN_RESETIDS 1
#define POSIX_SPAWN_SETPGROUP 2
#define POSIX_SPAWN_SETSIGDEF 4
#define POSIX_SPAWN_SETSIGMASK 8
#define POSIX_SPAWN_SETSCHEDPARAM 16
#define POSIX_SPAWN_SETSCHEDULER 32
#define POSIX_SPAWN_USEVFORK 64
#define POSIX_SPAWN_SETSID 128

/* Darwin: opaque pointers, not fat structs.  See the note above. */
typedef void *posix_spawnattr_t;
typedef void *posix_spawn_file_actions_t;

int posix_spawn(pid_t *__restrict, const char *__restrict, const posix_spawn_file_actions_t *,
	const posix_spawnattr_t *__restrict, char *const *__restrict, char *const *__restrict);
int posix_spawnp(pid_t *__restrict, const char *__restrict, const posix_spawn_file_actions_t *,
	const posix_spawnattr_t *__restrict, char *const *__restrict, char *const *__restrict);

int posix_spawnattr_init(posix_spawnattr_t *);
int posix_spawnattr_destroy(posix_spawnattr_t *);

int posix_spawnattr_setflags(posix_spawnattr_t *, short);
int posix_spawnattr_getflags(const posix_spawnattr_t *__restrict, short *__restrict);

int posix_spawnattr_setpgroup(posix_spawnattr_t *, pid_t);
int posix_spawnattr_getpgroup(const posix_spawnattr_t *__restrict, pid_t *__restrict);

int posix_spawnattr_setsigmask(posix_spawnattr_t *__restrict, const sigset_t *__restrict);
int posix_spawnattr_getsigmask(const posix_spawnattr_t *__restrict, sigset_t *__restrict);

int posix_spawnattr_setsigdefault(posix_spawnattr_t *__restrict, const sigset_t *__restrict);
int posix_spawnattr_getsigdefault(const posix_spawnattr_t *__restrict, sigset_t *__restrict);

int posix_spawnattr_setschedparam(posix_spawnattr_t *__restrict, const struct sched_param *__restrict);
int posix_spawnattr_getschedparam(const posix_spawnattr_t *__restrict, struct sched_param *__restrict);
int posix_spawnattr_setschedpolicy(posix_spawnattr_t *, int);
int posix_spawnattr_getschedpolicy(const posix_spawnattr_t *__restrict, int *__restrict);

int posix_spawn_file_actions_init(posix_spawn_file_actions_t *);
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *);

int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *__restrict, int, const char *__restrict, int, mode_t);
int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *, int);
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *, int, int);

/*
 * Darwin extensions.
 *
 * POSIX_SPAWN_CLOEXEC_DEFAULT closes every descriptor in the child except
 * the ones named by the file actions -- the value is from
 * xnu-3789.70.16 bsd/sys/spawn.h line 69.  libuv's process.c uses it so
 * that spawning does not leak the parent's descriptors.
 *
 * posix_spawn_file_actions_addinherit_np() is the "keep this one open"
 * counterpart; verified on device with posix_spawn_file_actions_init()
 * followed by addinherit_np(fa, 1): both returned 0.
 */
#define POSIX_SPAWN_CLOEXEC_DEFAULT	0x4000
#define POSIX_SPAWN_START_SUSPENDED	0x0080

int posix_spawn_file_actions_addinherit_np(posix_spawn_file_actions_t *, int);
int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *__restrict,
	const char *__restrict);

#ifdef __cplusplus
}
#endif

#endif /* _IOS_SPAWN_H */
