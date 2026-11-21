#!/bin/bash
# Build OpenSSH portable for armv7 iOS 10.x on Linux.  Verified with 10.6p2
# on an iPad 4 / iOS 10.3.3, run manually (never as a service) on port
# 22223 with auth, shell, scp and sftp all working.
#
# Why 10.6p2 and not something older:
#   * It was the first version tried and it built and ran, so nothing forced a
#     downgrade.  This is recorded as-is rather than dressed up as a survey.
#   * It needs OpenSSL >= 1.1.1; the openssl/ directory already builds 4.0.3
#     for armv7, and libcrypto.a from that build is reused here.
#   * The one thing that would break an older version is not a compile issue
#     but a configure issue: with -undefined dynamic_lookup every
#     AC_CHECK_FUNCS answer is a guess, so each release has to be re-pinned.
#
# The one thing that matters most about this build, and the reason build.sh is
# longer than the others: -undefined dynamic_lookup means the host linker
# accepts a call to any symbol, so *nothing* fails at link time.  Failure shows
# up later as "dyld: lazy symbol binding failed: Symbol not found: _foo" --
# sometimes in a re-exec'd child (sshd-session, sftp-server) that only runs
# after a successful handshake and authentication.  Three of the pins in
# ios-config.site (setproctitle, closefrom, getspnam) were found by running the
# finished binary on the device, not by reading a compile error.
#
# Usage:
#   LD64=.../x86_64-apple-darwin13.4.0-ld LD64_LIBS=... ./build.sh
#   OSSH_VERSION=10.6p2 ./build.sh        # the default
#   PREFIX=/var/mobile/tools ./build.sh   # install prefix baked into paths
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OSSH_VERSION="${OSSH_VERSION:-10.6p2}"
SRC="${OSSH_SRC:-$root/tmp/src/openssh-$OSSH_VERSION}"
OSSL="${OSSL:-$root/tmp/src/openssl-4.0.3}"
PREFIX="${PREFIX:-/var/mobile/tools}"

[ -d "$SRC" ] || {
    read -r U SHA _ <<<"$("$root/tools/fetch-src.sh" --lock openssh)"
    tarball="$("$root/tools/fetch-src.sh" openssh "$U" "$SHA")"
    rm -rf "$SRC"
    tar -C "$root/tmp/src" -xzf "$tarball"
}
[ -d "$SRC" ] || {
    echo "openssh source layout unexpected" >&2
    exit 1
}
[ -f "$OSSL/libssl.a" ] || {
    echo "==> building OpenSSL first (openssh's static dependency)"
    (cd "$root/openssl" && ./build.sh)
}
[ -f "$OSSL/libssl.a" ] || {
    echo "OpenSSL build did not produce $OSSL/libssl.a" >&2
    exit 1
}
export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-}}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }

# Must be tmp/stubs: that is where libSystem.tbd actually is.  The repo root is
# what openssl/build.sh and curl/build.sh use, and it does *not* work -- ld64
# answers "library not found for -lSystem" -- it only ever worked because
# those two builds were driven by tmux/build.sh's export_cc(), which sets
# STUBDIR to $WORK/stubs before calling anything.
export IOS_STUBDIR="${IOS_STUBDIR:-$root/tmp/stubs}"
export LD_LIBRARY_PATH="${LD64_LIBS:-}:${LD_LIBRARY_PATH:-}"

# All the "iOS doesn't have this" answers live here.  A config.site rather than
# --cache-file: autoconf rewrites the cache at the end of every run, so
# hand-edited cache values survive exactly one configure.
export CONFIG_SITE="$here/ios-config.site"

# Build a pristine copy so the tarball stays re-extractable and the source
# patches below are unambiguously "done by build.sh".
BUILD="${BUILD:-$root/tmp/openssh-build}"
rm -rf "$BUILD"; mkdir -p "$BUILD"
tar cf - -C "$SRC" . 2>/dev/null | tar xf - -C "$BUILD" || cp -a "$SRC/." "$BUILD/"
cd "$BUILD"
# iOS 10 has no ppoll(2) (dlsym MISS), and openssh 10.6 calls it unconditionally
# in the packet-timeout wait.  The production musl-era binary only survived
# because packet_timeout_ms defaults to -1 and lazy binding never resolved the
# symbol -- a time bomb, not a port.  poll(2) with a millisecond timeout is the
# exact equivalent for a single fd with no signal mask.
python3 - <<'PYEOF'
p = 'packet.c'
t = open(p).read()
old = 'ppoll(&pfd, 1, timespecp, NULL)'
new = 'poll(&pfd, 1, timespecp == NULL ? -1 : (int)(timespecp->tv_sec * 1000 + timespecp->tv_nsec / 1000000))'
n = t.count(old)
t = t.replace(old, new)
open(p, 'w').write(t)
print('    ppoll -> poll sites replaced:', n)
assert n >= 2, 'ppoll call sites not found'
PYEOF