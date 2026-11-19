#!/bin/bash
# Build ping (minimal ICMP echo, unprivileged SOCK_DGRAM + IPPROTO_ICMP)
# for armv7 iOS 10.x.  SDK sysroot mode per the 2026-11-15 ruling.
# No upstream: iputils is Linux-only, OpenBSD ping assumes setuid+raw,
# Apple's is closed -- see ping.c header for the platform reasoning.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"

export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
export IOS_STUBDIR="$HOME/ios-tool"   # hand-written stubs anchor -lSystem
export IOS_LD64="$LD64"
export LD_LIBRARY_PATH="${LD64_LIBS:-}:${LD_LIBRARY_PATH:-}"

CC="$root/tools/cc-wrapper.sh"
mkdir -p "$OUT"

"$CC" -O2 -Wall -o "$OUT/ping-armv7" "$here/ping.c"
ldid -S "$OUT/ping-armv7" 2>/dev/null || true
echo "==> $OUT/ping-armv7"
