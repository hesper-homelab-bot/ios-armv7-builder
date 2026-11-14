#!/bin/bash
# Build p7zip 17.05 (7za standalone) for armv7 iOS 10.x on Linux.
#
# Why 7za and not 7z/7z.so: 7za bundles every codec into one static binary --
# no Codecs/ plugins, no dlopen, nothing else to ship.  Its 17.05 codec set
# already covers what the 2007-era p7zip 4.57 on the device cannot read:
# LZMA2, xz, AES-256.
#
# Makefile base: makefile.linux_any_cpu, NOT makefile.macosx_gcc_32bits.
# The macosx variant drags in -m32 (the wrapper drops -arch but -m32 reaches
# clang and fights the armv7 target), -DENV_MACOSX and -framework
# CoreFoundation -- none of which this code needs.  The linux_cross_arm
# variant proves ARM needs no special defines beyond what any_cpu already
# has, so any_cpu + our CXX/CC is the whole recipe.
#
# Deviations from the stock any_cpu flags:
#   * OPTFLAGS -O -s -> -O2: `-s` is a link/strip flag; tools/cc-wrapper.sh
#     routes CFLAGS to compile lines only, so it would never reach the link
#     and just rides along as noise.  Stripping is the packager's business.
#   * -D_7ZIP_LARGE_PAGES dropped: there is no hugetlb machinery on iOS;
#     the macosx variant never defines it either.
#   * LOCAL_LIBS=-lpthread left as is: cc-wrapper absorbs -lpthread into
#     libSystem (see its -l case list).
#
# Source: git clone --depth 1 --branch v17.05
#         https://github.com/p7zip-project/p7zip  (commit a45b883)
# The classic sourceforge/Debian URLs were tried first and are dead from
# this host (HTML stub / 404 stub).
#
# Usage: ./build.sh          # output ../out/7za-<ver>-armv7 (UNSIGNED)
#        P7ZIP_SRC=... ./build.sh   # reuse an existing tree
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
P7ZIP_VERSION="${P7ZIP_VERSION:-17.05}"
SRC="${P7ZIP_SRC:-$HOME/scratch/p7zip/p7zip-src}"

[ -d "$SRC/CPP" ] || { echo "missing $SRC -- git clone --depth 1 --branch v$P7ZIP_VERSION https://github.com/p7zip-project/p7zip" >&2; exit 1; }

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$SRC"

# Cross-ify the machine makefile.  Idempotent by construction: cp overwrites,
# the seds match the pristine any_cpu lines.
cp -f makefile.linux_any_cpu makefile.machine
sed -i \
    -e "s|^CXX=.*|CXX=$HOME/ios-tool/cxx-wrapper.sh|" \
    -e "s|^CC=.*|CC=$root/tools/cc-wrapper.sh|" \
    -e "s|^OPTFLAGS=.*|OPTFLAGS=-O2|" \
    -e "s| -D_7ZIP_LARGE_PAGES||" \
    makefile.machine

# 7za -> CPP/7zip/Bundles/Alone.  MAKEFLAGS propagates -j into the sub-make;
# p7zip's makefiles carry explicit header deps and are parallel-safe.
MAKEFLAGS="-j$(nproc)" make 7za

BIN="$SRC/bin/7za"
[ -f "$BIN" ] || { echo "7za was not built" >&2; exit 1; }

mkdir -p "$root/out"
cp "$BIN" "$root/out/7za-$P7ZIP_VERSION-armv7"
echo "==> $root/out/7za-$P7ZIP_VERSION-armv7"
file "$root/out/7za-$P7ZIP_VERSION-armv7" | sed 's/^/    /'
echo "    (unsigned by design -- make-deb.sh signs the staged copy and"
echo "     asserts with ldid -e, per docs/toolchain.md §7/§10)"
