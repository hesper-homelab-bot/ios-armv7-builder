#!/bin/bash
# build-ios-compat.sh -- (re)build sysroot-overlay/usr/lib/libios-compat.a
#
# The compat stubs (see ios-compat.c) must be a DARWIN flat archive: ld64
# silently ignores GNU-format archives (toolchain.md §2), and this archive
# is appended to links by tools/cc-wrapper.sh.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"   # tools/sysroot-overlay-compat -> repo root
OUT="$root/sysroot-overlay/usr/lib/libios-compat.a"

export IOS_SYSROOT="$root/tmp/sysroot" \
       IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}" \
       IOS_LD64="${IOS_LD64:?set IOS_LD64}" \
       LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$(dirname "$OUT")"
"$root/tools/cc-wrapper.sh" -O1 -c "$here/ios-compat.c" -o "$w/ios-compat.o"
"$root/tools/darwin-ar" rcs "$OUT" "$w/ios-compat.o"
# verify the archive is usable by ld64 (Darwin flat, non-empty)
n=$(llvm-ar-21 t "$OUT" | wc -l)
[ "$n" -gt 0 ] || { echo "resulting archive has 0 members" >&2; exit 1; }
echo "==> $OUT ($n member)"
