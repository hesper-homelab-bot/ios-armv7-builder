#!/usr/bin/env python3
"""Split every 8-byte _Py_atomic load/store into two 4-byte atomics on
Apple armv7 (iOS 10.x, 32-bit).

WHY THIS IS NEEDED  (root cause, proven on device 2026-11-16)
------------------------------------------------------------
Apple's 32-bit ARM ABI gives `int64_t`/`uint64_t` **4-byte** alignment
(`_Alignof(int64_t) == 4`), but the ARM `ldrexd`/`strexd` instructions used
by compiler-rt's 8-byte `__atomic_*` helpers require **8-byte** alignment.
When clang emits an 8-byte atomic on a merely 4-byte-aligned object, the
CPU raises an alignment fault => **SIGBUS** (not a wrong value: an actual
bus error, immediate process death).

On-device probe (tools/ ../probes, reproduced verbatim):

    sizeof(int64_t)=8   _Alignof(int64_t)=4
    &g_val = 0x72024    (mod 8 = 4)
    __atomic_load_n(&g_val, __ATOMIC_RELAXED)  ->  Bus error: 10

    split into two 4-byte atomic reads            ->  value correct
    same 8-byte atomic on an 8-byte-aligned obj   ->  value correct

So the fix is: never let an 8-byte atomic touch a 4-byte-aligned object.
Read/write the low and high 32-bit halves separately (4-byte atomics are
reliable on this device) with a barrier in between.

WHY THE ORIGINAL PORT MISSED THIS
---------------------------------
The 3.13 port fixed exactly one function, `_Py_atomic_load_ullong_relaxed`,
because that was the one hit by the recursive-mutex deadlock.  The other
eighteen int64/uint64 entry points kept calling `__atomic_*` on 8-byte
values.  `_socket.socket()` died on
`_Py_atomic_load_int64_relaxed(&state->defaulttimeout)` inside
`init_sockobject()` -- 100% reproducible SIGBUS that produced **no crash
report** (the fault happens before CrashReporter can run).

SCOPE / LIMITS
--------------
Handled here: all five 8-byte load variants and all five store variants
(seq_cst, relaxed, acquire, release) -- the set that matters for the SIGBUS.

NOT handled: the read-modify-write ops (add / exchange / compare_exchange /
and / or).  Those cannot be emulated by splitting halves without destroying
atomicity; they need a lock or an ldrexd/strexd retry loop.  They were not
observed to fault in the tested paths, but if a new crash traces back to
one of them, that is where to look.

USAGE
-----
    python3 patch-atomic-armv7-align.py /path/to/cpython-src/Include/cpython/pyatomic_gcc.h

Idempotent: a second run detects the sentinel and exits cleanly.
Applies cleanly to both 3.13 and 3.14 (same file layout).
"""
import re
import sys

GUARD = "#if defined(__APPLE__) && defined(__arm__) && !defined(__aarch64__)"
# Appears in every body this script inserts; used to detect an already-patched
# tree (the plain `{ ... }` regexes stop matching once a body is multi-line).
SENTINEL = "__sync_synchronize();"

LOAD_TP = """    const volatile uint32_t *p32 = (const volatile uint32_t *)obj;
    uint32_t lo = __atomic_load_n(&p32[0], __ATOMIC_%(order)s);
    __sync_synchronize();
    uint32_t hi = __atomic_load_n(&p32[1], __ATOMIC_%(order)s);
    return (%(ret)s)(((uint64_t)hi << 32) | lo);
#else
    %(orig)s
#endif
"""

STORE_TP = """    volatile uint32_t *p32 = (volatile uint32_t *)obj;
    __atomic_store_n(&p32[0], (uint32_t)(value & 0xffffffffu), __ATOMIC_%(order)s);
    __sync_synchronize();
    __atomic_store_n(&p32[1], (uint32_t)((uint64_t)value >> 32), __ATOMIC_%(order)s);
#else
    %(orig)s
#endif
"""

LOADS = [("_Py_atomic_load_int64","int64_t","int64_t","SEQ_CST"),
         ("_Py_atomic_load_uint64","uint64_t","uint64_t","SEQ_CST"),
         ("_Py_atomic_load_int64_relaxed","int64_t","int64_t","RELAXED"),
         ("_Py_atomic_load_uint64_relaxed","uint64_t","uint64_t","RELAXED"),
         ("_Py_atomic_load_uint64_acquire","uint64_t","uint64_t","ACQUIRE")]
STORES = [("_Py_atomic_store_int64","int64_t","SEQ_CST"),
          ("_Py_atomic_store_uint64","uint64_t","SEQ_CST"),
          ("_Py_atomic_store_int64_relaxed","int64_t","RELAXED"),
          ("_Py_atomic_store_uint64_relaxed","uint64_t","RELAXED"),
          ("_Py_atomic_store_uint64_release","uint64_t","RELEASE")]

def process(path):
    src = open(path).read()

    # Sentinel for idempotency: our split bodies all contain this marker.
    # After the first run the simple `{ ... }` regexes no longer match, so
    # without this check a second run would report a misleading "MISS".
    if SENTINEL in src:
        n = src.count(SENTINEL)
        print("already applied (%d guarded functions found) -- nothing to do" % n)
        return

    out = src
    done = []
    missed = []

    def rewrite(name, kind, order, ret=None, argty=None):
        nonlocal out
        if kind == "load":
            # match:  static inline RET\nNAME(const ARG *obj)\n{ BODY }
            pat = re.compile(
                r"static inline %s\n%s\(const %s \*obj\)\n\{ (.*?) \}" % (ret, name, argty),
                re.S)
        else:
            pat = re.compile(
                r"static inline void\n%s\(%s \*obj, %s value\)\n\{ (.*?) \}" % (name, argty, argty),
                re.S)
        m = pat.search(out)
        if not m:
            missed.append(name); return
        if "__APPLE__" in m.group(1):
            print("  skip", name); return
        orig = m.group(1).strip()
        if kind == "load":
            body = LOAD_TP % {"order": order, "ret": ret, "orig": orig}
        else:
            body = STORE_TP % {"order": order, "orig": orig}
        newfn = m.group(0).replace("{ " + m.group(1) + " }",
                                   "{\n" + GUARD + "\n" + body + "}")
        out = out[:m.start()] + newfn + out[m.end():]
        done.append(name)

    for n, rt, at, o in LOADS:
        rewrite(n, "load", o, ret=rt, argty=at)
    for n, at, o in STORES:
        rewrite(n, "store", o, argty=at)

    open(path, "w").write(out)
    print("applied %d" % len(done))
    for d in done:
        print("   ", d)
    if missed:
        # Not fatal by itself, but on a supported version (3.13 / 3.14) an
        # unexpected MISS means the upstream file layout changed and the
        # SIGBUS would come back -- fail loudly rather than silently.
        print("NOT FOUND (%d) -- upstream layout changed?" % len(missed))
        for m_ in missed:
            print("   ", m_)
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(process(sys.argv[1]))
