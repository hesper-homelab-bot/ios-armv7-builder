#!/bin/bash
# Build pgrep/pkill (OpenBSD pkill 1.44 lineage, Darwin sysctl adaptation)
# for armv7 iOS 10.x.  SDK sysroot mode per the 2026-11-15 ruling -- the
# kinfo_proc/kern.procargs2 definitions must be the real Apple headers.
# One binary, two names: basename "pgrep" lists, "pkill" kills.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"

export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"   # hand-written stubs anchor -lSystem
export IOS_LD64="${IOS_LD64:-${LD64:-$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld}}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

CC="$root/tools/cc-wrapper.sh"
mkdir -p "$OUT"

# -fno-stack-protector: the SDK headers pull in ssp glue that iOS 10
# libSystem does not export as expected; keep the binary self-sufficient.
"$CC" -O2 -fno-stack-protector -Wall \
    -o "$OUT/pgrep-armv7" "$here/pgrep.c"

cp "$OUT/pgrep-armv7" "$OUT/pkill-armv7"
ldid -S "$OUT/pgrep-armv7" 2>/dev/null || true
ldid -S "$OUT/pkill-armv7" 2>/dev/null || true
echo "==> $OUT/pgrep-armv7 + pkill-armv7"
echo "    deploy trio, then: pgrep -f tailscaled ; pkill -f 'pattern'"
