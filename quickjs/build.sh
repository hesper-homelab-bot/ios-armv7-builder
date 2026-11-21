#!/bin/bash
# Build QuickJS (qjs interpreter) for armv7 iOS 10.x on Linux.
#
# Origin: this engine was the comparison baseline for the node.js port
# (docs/quickjs.md, phase 1: `qjs -e 'print(40+2)'` -> 42 on the device).
# Productization here means: pinned upstream source (sources.lock), a clean
# reproducible tree, the standard check-undefined gate, and a deb.
#
# The Makefile is hand-rolled (no configure).  CC/AR/RANLIB passed on the
# command line override the in-file $(CROSS_PREFIX)clang defaults, which is
# exactly how the repo's other non-configure packages build.
#
# Usage: ./quickjs/build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
QJS_VERSION="${QJS_VERSION:-2026-06-04}"
SRC="$root/tmp/src/quickjs-$QJS_VERSION"
CC="$root/tools/cc-wrapper.sh"

export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "missing $IOS_SYSROOT (docs/toolchain.md §16)" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld}}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export LD_LIBRARY_PATH="${LD64_LIBS:-$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib}:${LD_LIBRARY_PATH:-}"

[ -d "$SRC" ] || {
    read -r U SHA _ <<<"$("$root/tools/fetch-src.sh" --lock quickjs)"
    tarball="$("$root/tools/fetch-src.sh" quickjs "$U" "$SHA")"
    tar -C "$root/tmp/src" -xJf "$tarball"
}

cd "$SRC"
# clean any phase-1 leftovers: productization builds from the pristine tree
rm -f qjs qjsc libquickjs.a *.o

# quickjs-libc.c needs <crt_externs.h> (_NSGetEnviron).  The SDK is the public
# cut and does not carry it; the repo's sysroot-overlay does.  Do NOT add the
# whole overlay to -I (it shadows SDK headers -- sys/param.h cascade,
# docs/toolchain.md §23 note); point a dedicated include dir at the overlay
# and copy just this header.
ABIINC="$root/tmp/quickjs-abi-include"
mkdir -p "$ABIINC"
cp -f "$root/sysroot-overlay/usr/include/crt_externs.h" "$ABIINC/"

# A non-empty CROSS_PREFIX switches the Makefile to its host-qjsc path: the
# qjsc compiler (which generates repl.c / precompiled bytecode) is built with
# HOST_CC for the build host, while qjs itself is cross-built with our
# wrapper.  Without it, make compiles qjsc for armv7 and then tries to RUN it
# on the Linux host ("Syntax error: word unexpected").
make -j"$(nproc)" qjs \
    CROSS_PREFIX=armv7-ios10.3- HOST_CC=gcc \
    CC="$CC" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
    DEFINES="-I$ABIINC" \
    >/dev/null

# post-link gate (same as every other port)
[ -x qjs ] || { echo "qjs not produced" >&2; exit 1; }
"$root/tools/check-undefined.sh" qjs
echo "==> out/qjs-$QJS_VERSION-armv7"
