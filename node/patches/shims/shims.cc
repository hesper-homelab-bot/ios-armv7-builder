/*
 * Link-time shims for the armv7 iOS 10.3.3 Node port.
 *
 * Everything here exists because the final link uses
 * -undefined dynamic_lookup: undefined names are legal at link time and
 * become dyld errors at exec.  Each shim below removes one such error,
 * with the evidence noted inline (device probes, see
 * ~/scratch/link-prescan/REPORT.md).
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/time.h>

/*
 * C-1: __dso_handle.  Every C++ TU references it; 30 link inputs carry the
 * undefined symbol.  Device probe (dsocheck): a binary with the reference
 * but no definition dies at exec with
 *     dyld: Symbol not found: ____dso_handle  (exit 134)
 * before main() runs.  Darwin's crt defines it as an anchor for
 * atexit-style registrations; self-referential is the standard minimal
 * spelling and is what the probe verified runs.
 */
void *__dso_handle = (void *)&__dso_handle;

/*
 * C-3: __assert_fail.  Referenced by 83 objects (musl headers declare it).
 * The operative tbd lists it, but the device does not export it, and it has
 * no __assert_rtn to fall back on either (probed: NULL).  Self-contained:
 * print in the glibc format musl callers expect, then abort.
 */
void __assert_fail(const char *expr, const char *file, int line,
                   const char *func) {
    fprintf(stderr, "Assertion failed: (%s), function %s, file %s, line %d.\n",
            expr, func, file, line);
    abort();
}

/*
 * C-7: getsectiondata_64.  On armv7 the Mach-O header is always the 32-bit
 * one, so the 64-bit spelling is an alias by construction; V8 calls both
 * spellings depending on V8_HOST_ARCH_I32.  Device probe (getsect-probe)
 * verified getsectiondata returns a real __TEXT,__text.
 */
#include <stdint.h>
struct mach_header_shim { uint32_t magic; int32_t cputype; int32_t cpusubtype;
                          uint32_t filetype, ncmds, sizeofcmds, flags; };
struct mach_header_64_shim { uint32_t magic; int32_t cputype; int32_t cpusubtype;
                             uint32_t filetype, ncmds, sizeofcmds, flags, reserved; };
uint8_t *getsectiondata(const struct mach_header_shim *, const char *,
                        const char *, unsigned long *);
uint8_t *getsectiondata_64(const struct mach_header_64_shim *mhp,
                           const char *seg, const char *sect,
                           unsigned long *size) {
    return getsectiondata((const struct mach_header_shim *)mhp, seg, sect, size);
}

/*
 * C-8: __atomic_is_lock_free.  libSystem on this device exports the
 * load/store/cmpxchg family but not the query (probed).  Clang's
 * __atomic builtins call it for every atomic<T> with a runtime size.
 * Mirror of the compiler-rt spelling: natural-width objects up to a
 * pointer are lock-free when aligned.
 */
int __atomic_is_lock_free(size_t size, const void *ptr) {
    return size <= sizeof(void *) &&
           ((uintptr_t)ptr & (size - 1)) == 0;
}

/*
 * C-4: futimens / utimensat.  iOS 10's libSystem has futimes/utimes/lutimes
 * (all probed) but not the nanosecond variants, which arrived in iOS 11.
 * libuv's __APPLE__ fs path calls them (fs.c:255/1154/1188/1325), so
 * fs.utimes() would die on first use.  Coerce timespec to timeval -- the
 * nanoseconds are dropped, which is the best the platform offers.
 * AT_SYMLINK_NOFOLLOW routes to lutimes so lchmod-style semantics hold.
 */
#ifndef AT_FDCWD
#define AT_FDCWD (-2)
#endif
#ifndef AT_SYMLINK_NOFOLLOW
#define AT_SYMLINK_NOFOLLOW 0x0020
#endif

int futimens(int fd, const struct timespec times[2]) {
    struct timeval tv[2];
    for (int i = 0; i < 2; i++) {
        tv[i].tv_sec  = times[i].tv_sec;
        tv[i].tv_usec = times[i].tv_nsec / 1000;
    }
    return futimes(fd, tv);
}

int utimensat(int dirfd, const char *pathname,
              const struct timespec times[2], int flags) {
    struct timeval tv[2];
    for (int i = 0; i < 2; i++) {
        tv[i].tv_sec  = times[i].tv_sec;
        tv[i].tv_usec = times[i].tv_nsec / 1000;
    }
    (void)dirfd;   /* only AT_FDCWD reaches here through libuv */
    if (flags & AT_SYMLINK_NOFOLLOW) return lutimes(pathname, tv);
    return utimes(pathname, tv);
}

/*
 * C-9: v8::base::OS::ArmUsingHardFloat.  The definition lives in
 * platform-posix.cc under #if V8_OS_LINUX || V8_OS_FREEBSD, but the arm32
 * codegen references it (FlagList::PrintHelp path).  On this target the
 * compiler does not define __ARM_PCS_VFP (armv7-apple is soft-float PCS),
 * so the correct answer is false -- matching what a native arm32 build
 * would return.  (Prescan REPORT.md C-9; verified against the compile
 * flags used for the whole port.)
 */
extern "C" int _ZN2v84base2OS17ArmUsingHardFloatEv(void);
int _ZN2v84base2OS17ArmUsingHardFloatEv(void) { return 0; }

/*
 * C-10: PushAllRegistersAndIterateStack.  push_registers_asm.cc's __APPLE__
 * inline-asm blob defines the symbol WITHOUT the Mach-O leading underscore
 * (".globl PushAllRegistersAndIterateStack"), while stack.cc's extern "C"
 * reference carries it ("_PushAllRegistersAndIterateStack").  With
 * -undefined dynamic_lookup the reference stays lazy and dyld's flat lookup
 * cannot find the underscore-less definition (verified on device:
 * "dyld: lazy symbol binding failed: Symbol not found:
 * _PushAllRegistersAndIterateStack").  Trampoline: call the real
 * underscore-less symbol via an asm label.  Frame-count note: the asm blob
 * captures its own sp for conservative scanning; the trampoline's frame lies
 * between that sp and the caller's stack_end, so it stays inside the scanned
 * range and no register is missed.
 */
void PushAllRegistersAndIterateStack_asis(void *, void *, void *)
    __asm__("PushAllRegistersAndIterateStack");
extern "C" void PushAllRegistersAndIterateStack(void *visitor, void *stack_start, void *stack_end) {
    /*
     * The inline-asm blob in push_registers_asm.cc is THUMB code (assembled
     * in thumb state) but its symbol is NOT thumb-marked (n_desc lacks
     * N_ARM_THUMB_DEF; hence ld64's "ARM function not 4-byte aligned"
     * warning), so a plain call enters it in ARM mode where the thumb
     * encodings decode as conditional-false NOPs: the push happens (same
     * encoding in both modes), the mov/blx become NOPs, and control falls
     * through into chaos (the deterministic SIGILL).  Enter it explicitly
     * in thumb mode: blx with bit0 set on the target.
     */
    void *target = (void *)((uintptr_t)&PushAllRegistersAndIterateStack_asis | 1);
    register void *a0 __asm__("r0") = visitor;
    register void *a1 __asm__("r1") = stack_start;
    register void *a2 __asm__("r2") = stack_end;
    register void *a3 __asm__("r3") = target;
    __asm__ volatile("blx %3" : : "r"(a0), "r"(a1), "r"(a2), "r"(a3)
                     : "memory", "lr", "r4", "r5", "r6", "r7", "r8", "r9", "r10", "r11");
}

