#!/bin/bash
# Build OpenSSL (verified with 4.0.3) for armv7 iOS 10.x on Linux.
#
# Upstream status: the ios-cross/iphoneos-cross targets still exist in
# OpenSSL 4.x (Configurations/15-ios.conf, asm_arch armv4), but upstream
# never tests them.  Local adjustments, all documented in ../README.md:
#
#   * `-arch armv7` removed from the conf (Linux clang takes -target only)
#   * CROSS_TOP/CROSS_SDK env point the legacy -isysroot at our sysroot
#   * no-asm: the armv4 perlasm output uses ELF subtraction expressions
#     against OPENSSL_armcap_P that Mach-O rejects
#   * atomic_compat.c/.s: iOS 10 libSystem lacks __atomic_is_lock_free and
#     the generic __atomic_load/store/compare_exchange runtime helpers
#   * sysroot additions the build needs: TargetConditionals.h,
#     libkern/OSByteOrder.h, h_errno in netdb.h, struct in6_pktinfo and
#     the Darwin IPV6_PKTINFO(46)/RECVPKTINFO(61) values, and the whole
#     Darwin pthread.h (musl's pthread_once_t is 4 bytes; Darwin needs
#     12 with the 0x71B7236C signature - see the os_once crash in README)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OSSL_VERSION="${OSSL_VERSION:-4.0.3}"
SRC="$root/tmp/src/openssl-$OSSL_VERSION"
PREFIX="${PREFIX:-/var/mobile/openssl4}"    # isolated on purpose: never
                                            # overwrite the device's files
[ -f "$SRC/Configure" ] || {
    echo "missing $SRC (extract openssl-$OSSL_VERSION.tar.gz there)" >&2
    exit 1
}

export LD_LIBRARY_PATH="${LD64_LIBS:-}:${LD_LIBRARY_PATH:-}"
export IOS_SYSROOT="$root/tmp/sysroot"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first (makes the sysroot)" >&2; exit 1; }
export IOS_LD64="$LD64" IOS_STUBDIR="$root"
export CROSS_TOP="$root/tmp" CROSS_SDK=sysroot
mkdir -p "$root/tmp/SDKs"
ln -sfn ../sysroot "$root/tmp/SDKs/sysroot"

cd "$SRC"
sed -i 's/-arch armv7 //' Configurations/15-ios.conf

CC="$here/../tools/cc-wrapper.sh" \
AR="$here/../tools/darwin-ar" RANLIB="$here/../tools/darwin-ranlib" \
./Configure ios-cross no-asm no-shared no-tests no-docs \
    --prefix="$PREFIX" --openssldir="$PREFIX/etc/ssl" \
    > /dev/null
make -j"$(nproc)" > /dev/null

ldid -S apps/openssl
mkdir -p "$root/out"
cp apps/openssl "$root/out/openssl-$OSSL_VERSION-armv7"
echo "==> $root/out/openssl-$OSSL_VERSION-armv7"
echo "    install: scp it to $PREFIX/openssl on the device and ldid -S"
