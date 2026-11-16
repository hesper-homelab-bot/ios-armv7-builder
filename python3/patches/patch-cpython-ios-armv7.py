#!/usr/bin/env python3
"""Apply the iOS 10 / armv7 fixes to a CPython source tree.

These are the changes that made CPython 3.13.18 work on an iPad 4
(armv7, iOS 10.3.3) and are equally required for 3.14.x.
Written 2026-11-16 after the python3 port; extracted from the tweaks that
were applied ad hoc during that port so they can be re-applied to any
CPython version in one step.

Usage:
    python3 patch-cpython-ios-armv7.py /path/to/cpython-src

Each fix is idempotent (already-patched files are left alone) and reports
whether it applied.
"""
import os
import re
import sys

CHANGES = []


def record(name, path, ok, note=""):
    CHANGES.append((name, path, ok, note))


def read(path):
    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
        return fh.read()


def write(path, text):
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(text)


def patch_text(root, relpath, old, new, name, marker=None):
    """Replace `old` with `new` in relpath; idempotent via `marker`."""
    path = os.path.join(root, relpath)
    if not os.path.isfile(path):
        record(name, relpath, False, "file not found")
        return False
    src = read(path)
    if marker and marker in src:
        record(name, relpath, True, "already applied")
        return True
    if old not in src:
        record(name, relpath, False, "anchor text not found (version drift?)")
        return False
    write(path, src.replace(old, new, 1))
    record(name, relpath, True, "applied")
    return True


# --------------------------------------------------------------------------
# 1. 8-byte atomics are silently broken on this device
#    (clang forces 4-byte alignment for `unsigned long long` on Apple armv7,
#    so the 8-byte __atomic_* calls are unreliable).  Split them in half.
# --------------------------------------------------------------------------
LOAD_OLD = '''static inline unsigned long long
_Py_atomic_load_ullong_relaxed(const unsigned long long *obj)
{ return __atomic_load_n(obj, __ATOMIC_RELAXED); }'''

LOAD_NEW = '''static inline unsigned long long
_Py_atomic_load_ullong_relaxed(const unsigned long long *obj)
{
#if defined(__APPLE__) && defined(__arm__) && !defined(__aarch64__)
    /* Apple's armv7 ABI gives unsigned long long 4-byte alignment, so an
       8-byte __atomic_load_n may be emitted as an unaligned ldrexd and fail
       silently (returns garbage).  Read the two 32-bit halves instead; this
       device's 4-byte atomics are reliable (probed 2026-11-16). */
    const volatile uint32_t *p32 = (const volatile uint32_t *)obj;
    uint32_t lo = __atomic_load_n(&p32[0], __ATOMIC_RELAXED);
    __sync_synchronize();
    uint32_t hi = __atomic_load_n(&p32[1], __ATOMIC_RELAXED);
    return ((unsigned long long)hi << 32) | lo;
#else
    return __atomic_load_n(obj, __ATOMIC_RELAXED);
#endif
}'''

STORE_OLD = '''static inline void
_Py_atomic_store_ullong_relaxed(unsigned long long *obj,
                                unsigned long long value)
{ __atomic_store_n(obj, value, __ATOMIC_RELAXED); }'''

STORE_NEW = '''static inline void
_Py_atomic_store_ullong_relaxed(unsigned long long *obj,
                                unsigned long long value)
{
#if defined(__APPLE__) && defined(__arm__) && !defined(__aarch64__)
    /* See _Py_atomic_load_ullong_relaxed above: 8-byte atomics are unreliable
       here, so store the two 32-bit halves. */
    volatile uint32_t *p32 = (volatile uint32_t *)obj;
    __atomic_store_n(&p32[0], (uint32_t)(value & 0xffffffffu), __ATOMIC_RELAXED);
    __sync_synchronize();
    __atomic_store_n(&p32[1], (uint32_t)(value >> 32), __ATOMIC_RELAXED);
#else
    __atomic_store_n(obj, value, __ATOMIC_RELAXED);
#endif
}'''

# --------------------------------------------------------------------------
# 2. iOS redirects sys.stdout/stderr to os_log, which breaks a CLI python
#    (`print()` produces no output while os.write(1, ...) works).
# --------------------------------------------------------------------------
APPLESTREAM_OLD = '''#  if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#    define USE_APPLE_SYSTEM_LOG 1
#  else
#    define USE_APPLE_SYSTEM_LOG 0
#  endif'''

APPLESTREAM_NEW = '''// ios-armv7-builder (2026-11-16): upstream enables os_log on iOS, which
// replaces sys.stdout/sys.stderr with a SystemLog object -- a command line
// python3 then writes nothing to the terminal.  Disabled by default; pass
// -DPYTHON_IOS_USE_APPLE_SYSTEM_LOG=1 to get the upstream behaviour back.
#  ifndef PYTHON_IOS_USE_APPLE_SYSTEM_LOG
#    define PYTHON_IOS_USE_APPLE_SYSTEM_LOG 0
#  endif
#  if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE && PYTHON_IOS_USE_APPLE_SYSTEM_LOG
#    define USE_APPLE_SYSTEM_LOG 1
#  else
#    define USE_APPLE_SYSTEM_LOG 0
#  endif'''

# --------------------------------------------------------------------------
# 3. Alignment of 64-bit fields that are accessed with atomics.
#    clang ignores __attribute__((aligned(8))) on a *member* for the purposes
#    of atomic code generation, but the offsets still need to be consistent
#    between compilation units, so keep the annotations (they also make the
#    intent explicit).
# --------------------------------------------------------------------------
ALIGN_FIELDS = [
    ("Include/internal/pycore_interp_structs.h",
     r'^(\s*)int64_t interp_count;\s*$'),
    ("Include/internal/pycore_interp_structs.h",
     r'^(\s*)uint64_t _code_object_generation;\s*$'),
    ("Include/internal/pycore_interp_structs.h",
     r'^(\s*)uint64_t next_stackref;\s*$'),
    ("Include/internal/pycore_interp_structs.h",
     r'^(\s*)uint64_t next_unique_id;\s*$'),
    ("Include/internal/pycore_typeobject.h",
     r'^(\s*)int64_t interp_count;\s*$'),
    ("Include/internal/pycore_interp.h",
     r'^(\s*)uint64_t next_unique_id;\s*$'),
    ("Include/internal/pycore_lock.h",
     r'^(\s*)unsigned long long thread;\s*(//.*)?$'),
]


def main(root):
    # 1
    patch_text(root, "Include/cpython/pyatomic_gcc.h", LOAD_OLD, LOAD_NEW,
               "8-byte atomic load split", marker="probed 2026-11-16")
    patch_text(root, "Include/cpython/pyatomic_gcc.h", STORE_OLD, STORE_NEW,
               "8-byte atomic store split", marker="store the two 32-bit halves")

    # 2
    patch_text(root, "Python/pylifecycle.c", APPLESTREAM_OLD, APPLESTREAM_NEW,
               "disable Apple SystemLog stdout", marker="PYTHON_IOS_USE_APPLE_SYSTEM_LOG")

    # 3
    for rel, pattern in ALIGN_FIELDS:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            record("align field", rel, False, "file not found")
            continue
        src = read(path)
        new, n = re.subn(pattern + r'(?!\s*__attribute__)',
                         lambda m: f"{m.group(1)}{m.group(0).strip()} __attribute__((aligned(8)))",
                         src, flags=re.M)
        if n and new != src:
            write(path, new)
            record("align field", f"{rel} ({n})", True, "applied")
        else:
            record("align field", rel, True, "already applied / no match")

    print("=" * 62)
    ok = True
    for name, path, applied, note in CHANGES:
        flag = "OK " if applied else "FAIL"
        if not applied:
            ok = False
        print(f"[{flag}] {name:32s} {path:46s} {note}")
    print("=" * 62)
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
