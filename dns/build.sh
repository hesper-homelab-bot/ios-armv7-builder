#!/bin/bash
# Build dnsq (dig/nslookup/host, one binary three names) for armv7 iOS 10.x.
# SDK sysroot mode; self-contained stub resolver, no dependencies.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:-${LD64:-$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld}}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
CC="$root/tools/cc-wrapper.sh"
mkdir -p "$OUT"
"$CC" -O2 -Wall -o "$OUT/dnsq-armv7" "$here/dnsq.c"
for n in dig nslookup host; do
    cp "$OUT/dnsq-armv7" "$OUT/$n-armv7"
    ldid -S "$OUT/$n-armv7" 2>/dev/null || true
done
echo "==> $OUT/{dig,nslookup,host}-armv7"
