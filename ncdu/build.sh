#!/bin/bash
# Build ncdu 1.20 for armv7 iOS 10.x.  SDK sysroot mode.
# ncurses: the device ships headers (/usr/include) + libncursesw.5.dylib
# (tmux precedent — headers+dylib are pulled from the device into devhdr/).
# Walls (docs/ncdu.md):
#   - 宽字符头必须经 shim include(ncursesw/ncurses.h 才带 wrapped acs_map)
#   - 设备 dylib 只认**直接路径**链接:`-lncursesw` 的 -L 搜索不解析
#     libncursesw.5.dylib(版本化名,目录里无 libncursesw.dylib 软链;
#     IOS_DYLIBS 通道有路径怪癖)→ 把 dylib 当普通链接输入传入
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:-${LD64:-$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld}}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
CC="$root/tools/cc-wrapper.sh"
DHD="$here/devhdr"
mkdir -p "$OUT" "$DHD/shim"
[ -f "$DHD/shim/ncurses.h" ] || printf '#include <ncursesw/ncurses.h>\n' > "$DHD/shim/ncurses.h"
SRC="$here/src"
[ -d "$SRC" ] || { echo "missing $SRC (source tree)" >&2; exit 1; }
cd "$SRC"
if [ ! -f Makefile ]; then
  ac_cv_header_ncurses_h=yes CC="$CC" ./configure --host=armv7-apple-ios \
    --prefix=/var/mobile/tools/ncdu CPPFLAGS="-I$DHD/shim -I$DHD" \
    LDFLAGS="-L$DHD" LIBS="-lncursesw"
fi
make -j4 >/dev/null 2>&1 || true
# 手链:目标 + 设备 dylib 直接路径(运行时 dyld 按 install name 加载
# /usr/lib/libncursesw.5.dylib——设备原生存在)
rm -f ncdu
"$CC" -O2 -o "$OUT/ncdu4-armv7" src/*.o deps/strnatcmp.o "$DHD/libncursesw.5.dylib"
ldid -S "$OUT/ncdu4-armv7" 2>/dev/null || true
echo "==> $OUT/ncdu4-armv7"
