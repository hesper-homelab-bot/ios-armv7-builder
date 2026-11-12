#!/bin/bash
# Build jq 1.7.1 (with oniguruma 6.9.10) for armv7 iOS 10.x on Linux.
#
# jq 1.7 dropped the bundled oniguruma, so libonig is cross-built first.
# Both are pure C; the walls here are all toolchain-shape:
#
#   * oniguruma's libtool-generated libonig.la records its install
#     directory.  Installing it with DESTDIR to harvest the .a leaves the
#     .la claiming /var/mobile/tools, and libtool's "moved library"
#     relink logic chokes on that (eval syntax error).  Fix: copy the bare
#     libonig.a + headers into a clean directory and point
#     --with-oniguruma at it -- no .la in sight.
#   * libtool's --mode=link wants to build a shared libjq.dylib
#     (-Wl,-soname ...).  That path is useless on this device and the
#     toolchain has no use for it; --disable-shared --enable-static keeps
#     libtool in plain .a land and jq links statically against libonig.
#   * jq's builtin.c unconditionally redirects exp10 to Apple's __exp10
#     (`#define exp10 __exp10`), which is fine on real Darwin but musl's
#     math.h has no declaration for it.  Probe-verified live on the device
#     that __exp10 exists (__exp10(2.0) == 100.0), so the declaration was
#     added to sysroot-overlay/usr/include/math.h.
#
# Usage:
#   export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot \
#          IOS_STUBDIR=$HOME/ios-tool \
#          IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
#          LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
#   ./jq/build.sh          # -> ../out/jq-1.7.1-armv7
#   ./jq/make-deb.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
JQ_VERSION="${JQ_VERSION:-1.7.1}"
ONIG_VERSION="${ONIG_VERSION:-6.9.10}"
CC="$root/tools/cc-wrapper.sh"

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:?set IOS_LD64 to the cctools ld64}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

JQROOT="$HOME/ios-tool/jq-src"

# ------------------------------------------------------------- source ----
[ -d "$JQROOT/onig-$ONIG_VERSION" ] || {
    mkdir -p "$JQROOT"
    curl -fL "https://github.com/kkos/oniguruma/releases/download/v$ONIG_VERSION/onig-$ONIG_VERSION.tar.gz" -o /tmp/onig.tar.gz
    tar -C "$JQROOT" -xzf /tmp/onig.tar.gz
}
[ -d "$JQROOT/jq-$JQ_VERSION" ] || {
    curl -fL "https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-$JQ_VERSION.tar.gz" -o /tmp/jq.tar.gz
    tar -C "$JQROOT" -xzf /tmp/jq.tar.gz
}

# -------------------------------------------------------- oniguruma ----
if [ ! -f "$JQROOT/onig-clean/lib/libonig.a" ]; then
    cd "$JQROOT/onig-$ONIG_VERSION"
    [ -f ios-config.site ] || cp "$root/wget/ios-config.site" ios-config.site
    CC="$CC" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
        CONFIG_SITE="$PWD/ios-config.site" \
        ./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools \
            --enable-static --disable-shared >/dev/null
    make -j"$(nproc)" >/dev/null
    # verify the archive is a real darwin one before harvesting it
    n=$(llvm-ar-21 t src/.libs/libonig.a | wc -l)
    [ "$n" -gt 0 ] || { echo "libonig.a has 0 members" >&2; exit 1; }
    mkdir -p "$JQROOT/onig-clean/lib" "$JQROOT/onig-clean/include"
    cp src/.libs/libonig.a "$JQROOT/onig-clean/lib/"
    cp src/onig*.h "$JQROOT/onig-clean/include/"
    echo "==> oniguruma: $n members into onig-clean/"
fi

# ----------------------------------------------------------------- jq ----
cd "$JQROOT/jq-$JQ_VERSION"
[ -f ios-config.site ] || cp "$root/wget/ios-config.site" ios-config.site

make distclean >/dev/null 2>&1 || true
CC="$CC" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
    CONFIG_SITE="$PWD/ios-config.site" \
    ./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools \
        --with-oniguruma="$JQROOT/onig-clean" \
        --disable-shared --enable-static >/dev/null

make -j"$(nproc)" >/dev/null

ldid -S jq
mkdir -p "$root/out"
cp jq "$root/out/jq-$JQ_VERSION-armv7"
echo "==> $root/out/jq-$JQ_VERSION-armv7"
echo "    next: ./jq/make-deb.sh"
