#!/bin/bash
# Build GNU make 4.4.1 for armv7 iOS 10.x on Linux.
#
# Device-side rebuilds of small projects without a round-trip to the host.
# Zero external deps (NLS off -- no gettext on the device; guile off).
#
# Source: https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz
#
# Usage: ./build.sh          # output ../out/make-<ver>-armv7 (UNSIGNED)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
MAKE_VERSION="${MAKE_VERSION:-4.4.1}"
SRC="${MAKE_SRC:-$root/tmp/src/make-$MAKE_VERSION}"

[ -f "$SRC/configure" ] || {
    read -r U SHA _ <<<"$("$root/tools/fetch-src.sh" --lock make)"
    tarball="$("$root/tools/fetch-src.sh" make "$U" "$SHA")"
    rm -rf "$SRC"
    tar -C "$root/tmp/src" -xzf "$tarball"
}
[ -f "$SRC/configure" ] || { echo "make source layout unexpected" >&2; exit 1; }

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$SRC"
make distclean >/dev/null 2>&1 || true

# eaccess: glibc 同义词（= faccessat/access），设备 libSystem 没有——
# 恒真探针会把它放进 gnulib findprog-in；压掉走 access 回退。
# （dynamic_lookup 恒真探针陷阱：见 toolchain.md §15）
ac_cv_func_eaccess=no \
ac_cv_func_memrchr=no \
CC="$root/tools/cc-wrapper.sh" \
CFLAGS="-O2 -D_POSIX_VERSION=200809L -D_CS_PATH=1" \
./configure \
    --host=armv7-apple-darwin \
    --prefix=/var/mobile/tools/make \
    --disable-nls

# GNU ar 归档被 ld64 整体无视（"ignoring file ... building for iOS-armv7 but
# attempting to link with file built for iOS-armv7"——自相矛盾的警告，实为
# 归档格式问题，toolchain.md §2 同族坑）→ AR/RANLIB 必须 darwin 变体。
make -j"$(nproc)" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib"

BIN="$SRC/make"
[ -f "$BIN" ] || { echo "make was not built" >&2; exit 1; }
"$root/tools/check-undefined.sh" "$BIN"

mkdir -p "$root/out"
cp "$BIN" "$root/out/make-$MAKE_VERSION-armv7"
echo "==> $root/out/make-$MAKE_VERSION-armv7"
file "$root/out/make-$MAKE_VERSION-armv7" | sed 's/^/    /'
echo "    (unsigned by design -- make-deb.sh signs the staged copy)"
