#!/usr/bin/env python3
"""Replace OpenSSL perlasm's OPENSSL_armcap_P indirection with a constant.

Why
---
crypto/*/asm/*armv4*.pl emit, for every non-Windows target:

    .LOPENSSL_armcap:
    .word   OPENSSL_armcap_P-.L<function>     <- PIC-relative
    ...
        ldr     r12,.LOPENSSL_armcap
        adr     r2,.L<function>
        ldr     r12,[r12,r2]                  <- add base, get address
        ldr     r12,[r12]                     <- dereference to read the word

and for __APPLE__ specifically they expect the .word to hold the *address*
(absolute) and do a double dereference.

Neither form works for us:
  * The PIC-relative `.word sym-.Llocal` makes clang's integrated assembler
    fail with "symbol 'OPENSSL_armcap_P' can not be undefined in a subtraction
    expression", because we link with -undefined dynamic_lookup (the symbol is
    intentionally undefined at assembly time).
  * The absolute form produces ARM_RELOC_VANILLA text relocations, which ld64
    rejects inside a Mach-O bundle ("illegal text reloc ... to
    OPENSSL_armcap_P").

Solution: materialise the capability word as a compile-time constant.  The
device is an A6X (ARMv7-A with NEON), so ARMV7_NEON (1) is factually correct
and the assembly fast paths are genuinely usable.

Usage
-----
    python3 patch-perlasm-armcap.py /path/to/openssl-4.0.3
"""
import os
import re
import sys

PL_FILES = [
    "crypto/armv4cpuid.pl",
    "crypto/bn/asm/armv4-mont.pl",
    "crypto/bn/asm/armv4-gf2m.pl",
    "crypto/chacha/asm/chacha-armv4.pl",
    "crypto/poly1305/asm/poly1305-armv4.pl",
    "crypto/sha/asm/sha1-armv4-large.pl",
    "crypto/sha/asm/sha256-armv4.pl",
    "crypto/sha/asm/sha512-armv4.pl",
]

# 1) the data word that held the address now holds the constant
WORD_RE = re.compile(r'^([ \t]*\.word[ \t]+)OPENSSL_armcap_P(?:-\.[A-Za-z0-9_]+)?[ \t]*$',
                     re.M)

# 2) the load sequence: `ldr rX,.LOPENSSL_armcap` followed by up to two
#    dereferences that turn it into a value
LOAD_RE = re.compile(
    r'(?P<i>[ \t]*)ldr[ \t]+(?P<r>\w+)[ \t]*,[ \t]*\.?L?OPENSSL_armcap[ \t]*\n'
    r'(?:(?P=i)(?:adr|ldr)[ \t]+\w+[ \t]*,[^\n]*\n)?'
    r'(?:(?P=i)ldr[ \t]+(?P=r)[ \t]*,\[[^\]]*\][ \t]*(?:@[^\n]*)?\n)?'
)

# 3) stray dereferences left over from partial matches
SELF_DEREF_RE = re.compile(r'^[ \t]*ldr[ \t]+(\w+)[ \t]*,\[\1\][ \t]*(?:@[^\n]*)?\n', re.M)
BASEREG_DEREF_RE = re.compile(r'^[ \t]*ldr[ \t]+(\w+)[ \t]*,\[\w+,(\1)\][ \t]*(?:@[^\n]*)?\n', re.M)

# 4) drop the .hidden/.private_extern for the symbol (it is not referenced now)
HIDDEN_RE = re.compile(r'^[ \t]*\.(?:hidden|private_extern)[ \t]+_?OPENSSL_armcap_P[ \t]*\n', re.M)
# the symbol is no longer referenced, so its declaration can go too
EXTERN_RE = re.compile(r'^[ \t]*\.extern[ \t]+_?OPENSSL_armcap_P[ \t]*\n', re.M)


def patch(root: str) -> int:
    failures = []
    for rel in PL_FILES:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            failures.append(f"missing: {rel}")
            continue
        with open(path, encoding="utf-8", errors="surrogateescape") as fh:
            src = fh.read()
        out = WORD_RE.sub(lambda m: f"{m.group(1)}1", src)
        out = LOAD_RE.sub(lambda m: f"{m.group('i')}mov\t{m.group('r')},#1\n", out)
        out = SELF_DEREF_RE.sub("", out)
        out = BASEREG_DEREF_RE.sub("", out)
        out = HIDDEN_RE.sub("", out)
        out = EXTERN_RE.sub("", out)
        if out != src:
            with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
                fh.write(out)
            print(f"patched {rel}")
        else:
            print(f"unchanged {rel}")
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(patch(sys.argv[1]))
