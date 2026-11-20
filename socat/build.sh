#!/bin/bash
# Build socat 1.8.0.3 for armv7 iOS 10.x.  SDK sysroot mode.
# Walls (docs/socat.md):
#   - HAVE_GETRESUID/HAVE_GETRESGID 恒真探针(Linux-only API)→ config.h 压制
#   - libtool GNU-ar 归档 ld64 无视(§2)→ 手链全部 .o
#     (排除 procan*/filan_main —— 它们是另外两个二进制的 main;filan.o
#      本体保留,socat 引用它的 filan_fd)
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
SRC="$here/src"
[ -d "$SRC" ] || { echo "missing $SRC (source tree)" >&2; exit 1; }
cd "$SRC"
if [ ! -f Makefile ]; then
  CC="$CC" ./configure --host=armv7-apple-ios --prefix=/var/mobile/tools/socat \
    --disable-shared --enable-static
fi
sed -i 's|^#define HAVE_GETRESUID 1|/* #undef HAVE_GETRESUID */  /* Linux-only; probe lie */|; s|^#define HAVE_GETRESGID 1|/* #undef HAVE_GETRESGID */  /* Linux-only */|' config.h
make -j4 >/dev/null 2>&1 || true
OBJS=$(ls *.o | grep -vE "^(procan|procan_main|procan-cdefs|filan_main)\.o$")
"$CC" -O2 -o "$OUT/socat4-armv7" $OBJS
ldid -S "$OUT/socat4-armv7" 2>/dev/null || true
echo "==> $OUT/socat4-armv7"
