#ifndef _SYS_MMAN_H
#define _SYS_MMAN_H

/* musl's <sys/mman.h> is a Linux header.  Most of the constants happen to
 * coincide with Darwin's, which is why the tmux/curl/dropbear/OpenSSH builds
 * got this far with it -- MAP_SHARED(0x01), MAP_PRIVATE(0x02) and
 * MAP_FIXED(0x10) are the same on both.  The ones that do not coincide are
 * exactly the ones a program reaches for on this platform:
 *
 *   flag          Linux (musl)   Darwin
 *   MAP_ANON      0x0000020      0x0001000
 *   MAP_NORESERVE 0x0004000      0x0000040
 *   MAP_STACK     0x0002000      0x0000400
 *
 * The symptom is nasty because mmap(2) does not validate unknown flags the way
 * fcntl(2) does not validate unknown flags: it returns a real error instead of
 * silently ignoring them, so the failure looks like a bug in the caller.
 * OpenSSH's sshkey_shield_private() shields its host key with
 *     mmap(NULL, len, PROT_READ|PROT_WRITE,
 *         MAP_ANON|MAP_PRIVATE, -1, 0)
 * and with musl's value the kernel answers
 *     "Unable to shield host key: Bad file descriptor"
 * after which sshd refuses to start at all ("no hostkeys available").
 * Nothing about that message points at a header constant.
 *
 * This is the Darwin header, so a program written against it gets the right
 * numbers on iOS.  The POSIX-mandated values (PROT_*, MS_*, MCL_*) are the
 * same on both systems and are repeated as Darwin spells them. */

#ifdef __cplusplus
extern "C" {
#endif

#include <features.h>
#include <bits/alltypes.h>
/* NULL is used by every mmap() call site; upstream musl gets it
   transitively, the hand-made sysroot did not. */
#include <stddef.h>

#define MAP_FAILED ((void *)-1)

#define MAP_SHARED     0x0001
#define MAP_PRIVATE    0x0002
#define MAP_FIXED      0x0010
#define MAP_ANON       0x1000         /* or MAP_ANONYMOUS */
#define MAP_ANONYMOUS  MAP_ANON
#define MAP_NORESERVE  0x0040
#define MAP_STACK      0x0400
#define MAP_JIT        0x0800         /* iOS 18+; harmless to declare */
#define MAP_FILE       0x0000

#define PROT_NONE      0x00
#define PROT_READ      0x01
#define PROT_WRITE     0x02
#define PROT_EXEC      0x04

#define MS_ASYNC       0x0001
#define MS_INVALIDATE  0x0002
#define MS_SYNC        0x0010

#define MCL_CURRENT    0x0001
#define MCL_FUTURE     0x0002

int madvise(void *, size_t, int);
/* Darwin's advice values; musl's coincide at 0-4 but diverge above. */
#define MADV_NORMAL      0
#define MADV_RANDOM      1
#define MADV_SEQUENTIAL  2
#define MADV_WILLNEED    3
#define MADV_DONTNEED    4
#define MADV_FREE        5           /* macOS only; iOS answers EINVAL */
#define MADV_ZERO_WIRED_PAGES 6
#define MADV_FREE_REUSABLE 7
#define MADV_FREE_REUSE 8
#define MADV_CAN_REUSE 9
#define MADV_PAGEOUT 10

#define POSIX_MADV_NORMAL     MADV_NORMAL
#define POSIX_MADV_RANDOM     MADV_RANDOM
#define POSIX_MADV_SEQUENTIAL MADV_SEQUENTIAL
#define POSIX_MADV_WILLNEED   MADV_WILLNEED
#define POSIX_MADV_DONTNEED   MADV_DONTNEED

/* MADV_DONTDUMP is musl's spelling (Linux value 16); OpenSSH's
   sshkey_shield_private() calls madvise(..., MADV_DONTDUMP) on the Annalised
   pre-key buffer, so a port must have the macro even though the answer it gets
   from iOS is EINVAL.  Declared as an alias of Darwin's nearest equivalent
   (MADV_ZERO_WIRED_PAGES has the same intent of "keep core dumps clean") --
   in practice either name returns EINVAL on iOS 10 and the call is ignored,
   which is the outcome the "#if defined(MADV_DONTDUMP) && !MAP_CONCEAL" guard
   in sshkey.c is written to tolerate. */
#define MADV_DONTDUMP         MADV_ZERO_WIRED_PAGES

void *mmap(void *, size_t, int, int, int, off_t);
int munmap(void *, size_t);
int mprotect(void *, size_t, int);
int msync(void *, size_t, int);
int mlock(const void *, size_t);
int munlock(const void *, size_t);
int mlockall(int);
int munlockall(void);

#ifdef __cplusplus
}
#endif

#include <mach/vm_statistics.h>  /* VM_MAKE_TAG, as on Apple */

#endif
