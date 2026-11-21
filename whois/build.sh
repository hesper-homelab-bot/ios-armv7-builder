#!/bin/bash
# Build whois 5.6.6 (rfc1036/whois) for armv7 iOS 10.x on Linux.
#
# The cleanest port so far: ZERO probe overrides, ZERO patches.
#   * config.h platform-detects via predefined macros and has a proper
#     __APPLE__ && __MACH__ branch (NLS stays off: ENABLE_NLS is gated on
#     __GLIBC__/__FreeBSD__, neither defined for armv7-apple-ios);
#   * data lists (tld_serv, ip_del, ...) compile into headers via the
#     bundled perl scripts -- no runtime data files to ship;
#   * iconv/libidn/crypt are opt-in and stay opt-out because PKG_CONFIG is
#     pointed at /bin/false (blocks the host pkg-config autodetection from
#     leaking host -I/-L into a cross build) and HAVE_ICONV is not set.
#
# Source: git clone --depth 1 https://github.com/rfc1036/whois
#         (commit 54d60d8)
#
# Usage: ./build.sh          # output ../out/whois-<ver>-armv7 (UNSIGNED)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# Pinned upstream master-commit tarball (whois has no releases; the lock row
# carries the 2026-11-21 commit and its real sha256 -- "no release" does not
# mean "unpinnable").  Fetched through the standard verified path instead of
# the old manual git clone into ~/scratch.
SRC="${WHOIS_SRC:-$root/tmp/src/whois-1024386831c8ee4e0ae24026fa932771bf369fe9}"
[ -f "$SRC/Makefile" ] || {
    read -r U SHA _ <<<"$("$root/tools/fetch-src.sh" --lock whois)"
    tarball="$("$root/tools/fetch-src.sh" whois "$U" "$SHA")"
    rm -rf "$SRC"
    tar -C "$root/tmp/src" -xzf "$tarball"
}
[ -f "$SRC/Makefile" ] || { echo "whois source layout unexpected" >&2; exit 1; }

# Upstream utils.c #defines _XOPEN_SOURCE 500 to reach strdup, but strdup was
# standardized in POSIX 2008: on Darwin headers that macro *hides* it
# ("implicit declaration of strdup" -- Linux glibc exposes it via
# _DEFAULT_SOURCE, which is why upstream never sees this).  Bump to 700
# (SUSv4); everything utils.c uses is still declared.
sed -i 's/#define _XOPEN_SOURCE 500/#define _XOPEN_SOURCE 700/' "$SRC/utils.c"

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$SRC"

# 1. generated headers (version from debian/changelog; data lists -> .h)
make version.h as_del.h ip_del.h ip6_del.h new_gtlds.h \
     nic_handles.h tld_serv.h servers_charset.h PERL=perl >/dev/null
WHOIS_VERSION="$(sed -n 's/^#define VERSION "\(.*\)"/\1/p' version.h)"
[ -n "$WHOIS_VERSION" ] || { echo "cannot read VERSION from version.h" >&2; exit 1; }

# 2. whois only (mkpasswd needs libcrypt; skip).  HAVE_GETOPT_LONG is real
#    on the device (libSystem) -- stated explicitly rather than relying on
#    config.h's version-gated Apple branch.
make whois CC="$root/tools/cc-wrapper.sh" CFLAGS="-O2" \
     PKG_CONFIG=/bin/false DEFS="-DHAVE_GETOPT_LONG"

BIN="$SRC/whois"
[ -f "$BIN" ] || { echo "whois was not built" >&2; exit 1; }

# 3. post-link audit (the dynamic_lookup gate -- see rsync/build.sh)
"$root/tools/check-undefined.sh" "$BIN"

mkdir -p "$root/out"
cp "$BIN" "$root/out/whois-$WHOIS_VERSION-armv7"
echo "==> $root/out/whois-$WHOIS_VERSION-armv7"
file "$root/out/whois-$WHOIS_VERSION-armv7" | sed 's/^/    /'
echo "    (unsigned by design -- make-deb.sh signs the staged copy)"
