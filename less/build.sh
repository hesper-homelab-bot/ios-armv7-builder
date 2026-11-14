#!/bin/bash
# Build less v668 for armv7 iOS 10.x on Linux.
#
# Curses strategy (the vim precedent, docs in vim/build.sh WALL 1):
#   * ncurses HEADERS are already in the sysroot (pulled off the device
#     during the vim port: ncurses.h/term.h/ncursesw/, ncurses 5.7 wide API);
#   * less links the DEVICE's own /usr/lib/libncursesw.5.dylib -- a cached
#     copy at $HOME/ios-tool/device-libs/libncursesw.5.dylib is put on the
#     link line explicitly, because cc-wrapper silently absorbs -lncursesw
#     (it is in the "inside libSystem" drop list, which is wrong for
#     curses) and the audit gate would then flag tgetent/tigetstr.
#   * device /usr/share/terminfo exists (verified 2026-11-14), so less can
#     resolve TERM entries at runtime.
#
# Source: the official release tarball
#         https://www.greenwoodsoftware.com/less/less-668.tar.gz -- it ships
#         the pre-generated configure/funcs.h/help.c that the git tree
#         lacks (git tree = configure.ac only + generated-file holes; both
#         paths are supported below, the tarball is the default).
#
# Usage: ./build.sh          # output ../out/less-<ver>-armv7 (UNSIGNED)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
LESS_VERSION="${LESS_VERSION:-668}"
SRC="${LESS_SRC:-$HOME/scratch/less/less-$LESS_VERSION}"
NCDYLIB="${NCDYLIB:-$HOME/ios-tool/device-libs/libncursesw.5.dylib}"

[ -x "$SRC/configure" ] || [ -f "$SRC/configure.ac" ] || { echo "missing $SRC -- download https://www.greenwoodsoftware.com/less/less-$LESS_VERSION.tar.gz (or git clone --branch v$LESS_VERSION https://github.com/gwsw/less.git)" >&2; exit 1; }
[ -s "$NCDYLIB" ] || { echo "missing $NCDYLIB -- cache the device dylib (see vim/build.sh ensure_ncurses_dylib)" >&2; exit 1; }

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$SRC"

# 1. configure: the release tarball ships one; only the git tree needs
#    in-tree regeneration (autoconf)
if [ ! -x ./configure ]; then
    make -f Makefile.aut configure >/dev/null 2>&1
    [ -x ./configure ] || { echo "configure regeneration failed" >&2; exit 1; }
fi

# 2. configure in cross mode
CC="$root/tools/cc-wrapper.sh" \
CFLAGS="-O2" \
./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools/less

# 3. curses: swap whatever curses -l flags configure picked for the device
#    dylib (cc-wrapper drops -lncurses*; a real .dylib on the link line
#    survives as an object input -- the vim approach).
sed -i "s|-lncursesw|$NCDYLIB|g; s|-lncurses|$NCDYLIB|g; s|-lcurses|$NCDYLIB|g; s|-ltermcap|$NCDYLIB|g; s|-ltinfo|$NCDYLIB|g" Makefile
grep -n "^LIBS" Makefile | sed 's/^/    LIBS: /' || true

# 3.5. funcs.h is a generated file (git tree lacks it; the release tarball
#      ships it).  Generate only when missing or main.o has no rule for it.
[ -f funcs.h ] || grep -h '^public [^;]*$' ./*.c | sed 's/$/;/' > funcs.h

# 4. build + audit
make -j"$(nproc)"

BIN="$SRC/less"
[ -f "$BIN" ] || { echo "less was not built" >&2; exit 1; }
"$root/tools/check-undefined.sh" "$BIN"

mkdir -p "$root/out"
cp "$BIN" "$root/out/less-$LESS_VERSION-armv7"
echo "==> $root/out/less-$LESS_VERSION-armv7"
file "$root/out/less-$LESS_VERSION-armv7" | sed 's/^/    /'
echo "    (unsigned by design -- make-deb.sh signs the staged copy;"
echo "     runtime terminfo comes from the device's /usr/share/terminfo)"
