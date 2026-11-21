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
    read -r U SHA _ <<<"$("$root/tools/fetch-src.sh" --lock openssl)"
    tarball="$("$root/tools/fetch-src.sh" openssl "$U" "$SHA")"
    rm -rf "$SRC"
    tar -C "$root/tmp/src" -xzf "$tarball"
}
[ -f "$SRC/Configure" ] || { echo "openssl source layout unexpected" >&2; exit 1; }

export LD_LIBRARY_PATH="${LD64_LIBS:-$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib}:${LD_LIBRARY_PATH:-}"
# SDK-mode contract (toolchain.md §1); the old musl sysroot remains the
# explicit opt-in via IOS_SYSROOT for historical reproductions
export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "missing $IOS_SYSROOT (bootstrap-toolchain.sh stage 3)" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld}}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
# 15-ios.conf assembles -isysroot $(CROSS_TOP)/SDKs/$(CROSS_SDK): present any
# sysroot through that shape with a link
mkdir -p "$root/tmp/SDKs"
rm -f "$root/tmp/SDKs/sdk"
ln -sfn "$IOS_SYSROOT" "$root/tmp/SDKs/sdk"
export CROSS_TOP="$root/tmp" CROSS_SDK=sdk

cd "$SRC"
sed -i 's/-arch armv7 //' Configurations/15-ios.conf

# atomic runtime helpers: a dlsym probe on the live device
# (tools/device-symprobe.sh, 2026-11-21) showed libSystem DOES export the full
# set (__atomic_is_lock_free, __atomic_load/store/fetch_add_8 ...), so the
# spinlock compat in atomic_compat.c is NOT needed -- the native helpers win.
# atomic_compat.c/atomic_alias.s stay in the tree as the record of two walls:
# the alias-stub ld64 text-relocation lesson and the -D rename that collided
# with the clang builtin.
export CC="$here/../tools/cc-wrapper.sh"
export AR="$here/../tools/darwin-ar"
export RANLIB="$here/../tools/darwin-ranlib"

./Configure ios-cross no-asm no-shared no-tests no-docs \
    --prefix="$PREFIX" --openssldir="$PREFIX/etc/ssl" \
    LDFLAGS="$CCOBJ" \
    > /dev/null
make -j"$(nproc)" > /dev/null

ldid -S apps/openssl
mkdir -p "$root/out"
cp apps/openssl "$root/out/openssl-$OSSL_VERSION-armv7"
echo "==> $root/out/openssl-$OSSL_VERSION-armv7"
echo "    install: scp it to $PREFIX/openssl on the device and ldid -S"
