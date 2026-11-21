#!/bin/bash
# Build curl (verified with 8.16.0) for armv7 iOS 10.x on Linux.
#
# Depends on an OpenSSL built by ../openssl/build.sh: curl links libssl.a and
# libcrypto.a statically, so there is no runtime dependency on libssl.dylib.
#
# Everything here was discovered through on-device crashes; see ../README.md
# for the full ABI story.  The three that matter most for curl:
#
#   * SOCK_NONBLOCK / SOCK_CLOEXEC do not exist on iOS 10.  musl defines them
#     as Linux type flags (0x80000 / 0x80000); curl ORs SOCK_NONBLOCK into
#     the socket() type, which the kernel rejects with EINVAL, making every
#     connection fail in ~1 ms with "Failed initialization".  The sysroot
#     undefines both so curl falls back to fcntl(F_SETFL).
#   * struct sockaddr needs Darwin's leading sa_len byte (and sockaddr_in
#     gains sin_len).  Without it, inet_ntop() reads a 16-bit family at
#     offset 0 and returns EAFNOSUPPORT.
#   * configure's link tests always "succeed" because we link with
#     -undefined dynamic_lookup, so curl detects Linux-only functions
#     (eventfd, pipe2, accept4, recvmmsg, sendmmsg, getpass_r, gsasl) that
#     do not exist on iOS.  They are undefined in lib/curl_config.h below.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
CURL_VERSION="${CURL_VERSION:-8.16.0}"
SRC="$root/tmp/src/curl-$CURL_VERSION"
OSSL="${OSSL:-$root/tmp/src/openssl-4.0.3}"
PREFIX="${PREFIX:-/var/mobile/tools}"

[ -d "$SRC" ] || {
    echo "missing $SRC" >&2
    echo "  sources.lock row 'curl' -- verify/fetch with:" >&2
    echo "    $root/tools/fetch-src.sh --lock curl    (then extract to $root/tmp/src/)" >&2
    exit 1
}
[ -f "$OSSL/libssl.a" ] || { echo "build OpenSSL first (openssl/build.sh)" >&2; exit 1; }
# sysroot: the 2026-11-15 ruling makes the REAL Apple SDK the default for
# ports.  curl 8.16.0 predated it and shipped with the musl-derived sysroot,
# whose Linux TCP option numbers made the default keepalive setup set
# TCP_NOPUSH (musl TCP_KEEPIDLE=4 collides with Darwin's 0x04) -- every
# request then sat corked in the kernel for ~5s (device curl report,
# 2026-11-19).  The SDK's own headers carry the real Darwin constants.
# Override with IOS_SYSROOT=$root/tmp/sysroot for the legacy musl build.
export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "missing $IOS_SYSROOT (see docs/toolchain.md §16)" >&2; exit 1; }
# env defaults embedded (toolchain.md §1 landmine, 4th occurrence): a fresh
# shell must never depend on the caller having exported the toolchain vars
export IOS_LD64="${IOS_LD64:-${LD64:-$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld}}"
export IOS_STUBDIR="$HOME/ios-tool"
export LD_LIBRARY_PATH="${LD64_LIBS:-$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib}:${LD_LIBRARY_PATH:-}"
export CROSS_TOP="$(dirname "$IOS_SYSROOT")" CROSS_SDK="$(basename "$IOS_SYSROOT")"

# configure looks for <prefix>/lib/libssl.a; OpenSSL's build tree keeps the
# archives in its root.  Give it the layout it expects.
mkdir -p "$OSSL/lib"
ln -sfn ../libcrypto.a "$OSSL/lib/libcrypto.a"
ln -sfn ../libssl.a "$OSSL/lib/libssl.a"

cd "$SRC"
make distclean >/dev/null 2>&1 || true

export CC="$root/tools/cc-wrapper.sh" AR="$root/tools/darwin-ar" \
RANLIB="$root/tools/darwin-ranlib"

# __atomic_is_lock_free shim (docs/go.md wall #7): the OpenSSL 4.0.3 static
# archives (2026-11-16 rebuild) reference the clang builtin, iOS 10 libSystem
# has the load/store/CAS operators but NOT the predicate -- same dangling
# reference nginx hit.  Link the shared honest thumb shim.
C8OBJ="$root/tmp/curl-c8fixed.o"
mkdir -p "$root/tmp"
"$CC" -c "$root/tools/shims/c8fixed.S" -o "$C8OBJ"

# zlib (gzip/deflate transfer encoding).  Reuses the zlib 1.3.1 that
# git/build.sh already cross-builds (same pinned source, same darwin-ar
# conversion, docs/toolchain.md §2) instead of building a second copy:
# configure wants <prefix>/lib/libz.a + <prefix>/include/zlib.h, the git
# build lays both at the source-tree root, so present that shape.
ZLIB_SRC="${ZLIB:-$HOME/ios-tool/zlib-src/zlib-1.3.1}"
if [ ! -f "$ZLIB_SRC/libz.a" ]; then
    echo "missing cross zlib: $ZLIB_SRC/libz.a" >&2
    echo "  build it first: (cd git && ./build.sh)   # or set ZLIB=" >&2
    exit 1
fi
ZLIBABI="$root/tmp/curl-zlib-abi"
mkdir -p "$ZLIBABI/lib" "$ZLIBABI/include"
cp -f "$ZLIB_SRC/libz.a" "$ZLIBABI/lib/"
cp -f "$ZLIB_SRC/zlib.h" "$ZLIB_SRC/zconf.h" "$ZLIBABI/include/"

./configure --host=armv7-apple-darwin --prefix="$PREFIX" \
    --disable-shared --enable-static \
    --with-openssl="$OSSL" \
    --with-zlib="$ZLIBABI" \
    --without-brotli --without-zstd \
    --without-libpsl --without-libidn2 --without-nghttp2 \
    --without-libgsasl \
    --disable-ldap --disable-ldaps --disable-manual \
    --disable-threaded-resolver \
    LDFLAGS="$C8OBJ" \
    >/dev/null

# Link tests lie (see header comment): turn off everything iOS 10 lacks.
for fn in HAVE_EVENTFD HAVE_SYS_EVENTFD_H HAVE_PIPE2 HAVE_ACCEPT4 \
          HAVE_RECVMMSG HAVE_SENDMMSG HAVE_GETPASS_R \
          HAVE_GETADDRINFO_A HAVE_PTHREAD_SETNAME_NP; do
    sed -i "s|^#define $fn 1\$|/* #undef $fn */|" lib/curl_config.h
done

make -j"$(nproc)" >/dev/null

ldid -S src/curl
mkdir -p "$root/out"
cp src/curl "$root/out/curl-$CURL_VERSION-armv7"
echo "==> $root/out/curl-$CURL_VERSION-armv7"
echo "    install: scp to $PREFIX/curl, then ldid -S on the device"
echo "    set SSL_CERT_FILE=/etc/ssl/cert.pem for HTTPS"
