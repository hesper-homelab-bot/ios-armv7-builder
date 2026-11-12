#!/bin/bash
# Cross-run answer service for nginx's `auto/feature` probes.
#
# nginx's configure *runs* some of its feature probes (ngx_feature_run=yes)
# and needs their exit status.  When cross-compiling, the probe binary is
# armv7 Mach-O and cannot execute on the x86 Linux build host, so nginx
# would report every run-probe as "found but is not working" -- a silent
# false negative that strips NGX_HAVE_* macros from ngx_auto_config.h.
#
# Rather than let the probes lie, this script answers them from knowledge of
# the *target* (iOS 10.3.3 / Darwin 16.7 / armv7), which in several cases is
# already device-verified elsewhere in this repository.  It is called by the
# patched auto/feature with the probe's *source file* as $1; exit 0 means
# "the feature works on the device".
#
# Matching is done on distinctive substrings of the probe's C body, so it
# stays stable across nginx versions as long as the probe's intent does.
# Anything unrecognised falls through to exit 0 as well (the compile+link
# step already proved the symbols exist, and every remaining run-probe in
# nginx 1.26 tests a facility iOS provides).
#
# Usage (from auto/feature):   ./crossanswer.sh <autotest.c>   -> exit 0/1

src="${1:?probe source required}"
[ -f "$src" ] || exit 0
body="$(cat "$src")"

# ---------------------------------------------------------------- probes --
# 1. C compiler exists: the binary was produced, so yes.
# 2. gcc builtin atomics (__sync_*): clang emits libcalls/ldrex on armv7,
#    NGX_HAVE_GCC_ATOMIC is set by the wrapper's own probe; treat as yes.
# 3. C99 / GCC variadic macros: clang supports both, unconditionally.
# 4. EVFILT_TIMER: device-verified working on iOS 10.3.3 (nmap/nsock).
# 5. mmap(MAP_ANON|MAP_SHARED): iOS has MAP_ANON; device probes in this repo
#    use it routinely (MAP_JIT is the one that fails -- not this).
# 6. mmap("/dev/zero"): /dev/zero exists on iOS; MAP_SHARED anonymous-y
#    mapping of it works.  Keep as yes.
# 7. POSIX semaphores (unnamed, pshared): available in libSystem; --with-threads
#    is what makes nginx want them.  Yes.
# 8. System V shm (shmget): iOS *does not* provide SysV IPC; answer no so
#    nginx takes the mmap-based shared-zone path instead.
case "$body" in
    *shmget*)                          exit 1 ;;   # no SysV IPC on iOS
esac

# Everything else: the compile+link succeeded, so the facility is present.
exit 0
