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

[ -d "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
[ -f "$OSSL/libssl.a" ] || { echo "build OpenSSL first (openssl/build.sh)" >&2; exit 1; }
export IOS_SYSROOT="$root/tmp/sysroot"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }
export IOS_LD64="$LD64" IOS_STUBDIR="$root"
export LD_LIBRARY_PATH="${LD64_LIBS:-}:${LD_LIBRARY_PATH:-}"
export CROSS_TOP="$root/tmp" CROSS_SDK=sysroot

# configure looks for <prefix>/lib/libssl.a; OpenSSL's build tree keeps the
# archives in its root.  Give it the layout it expects.
mkdir -p "$OSSL/lib"
ln -sfn ../libcrypto.a "$OSSL/lib/libcrypto.a"
ln -sfn ../libssl.a "$OSSL/lib/libssl.a"

cd "$SRC"
make distclean >/dev/null 2>&1 || true

CC="$root/tools/cc-wrapper.sh" AR="$root/tools/darwin-ar" \
RANLIB="$root/tools/darwin-ranlib" \
./configure --host=armv7-apple-darwin --prefix="$PREFIX" \
    --disable-shared --enable-static \
    --with-openssl="$OSSL" \
    --without-zlib --without-brotli --without-zstd \
    --without-libpsl --without-libidn2 --without-nghttp2 \
    --without-libgsasl \
    --disable-ldap --disable-ldaps --disable-manual \
    --disable-threaded-resolver \
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
