#!/bin/bash
# Package the armv7 lsof build into a .deb for the APT repo.
#
# Mirrors ../dropbear/make-deb.sh: the binary installs under /var/mobile so
# removing the package leaves the device as it was, and nothing in /usr is
# touched.  Unlike the SSH packages there are no tunables -- lsof takes no
# port, writes no config, runs no daemon -- so there is no CUSTOM routing:
# every build of a given version is the same package and lands in out/,
# which is what scripts/make-repo.sh scans.
#
# Usage:
#   ./lsof/make-deb.sh                 # uses ../out/lsof-*-armv7
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
LSOF_VERSION="${LSOF_VERSION:-4.99.7}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"

# Same signing contract as every other make-deb.sh here: host ldid, failures
# loud, and the result asserted with ldid -e (exit 0 only on a signed file).
# An unsigned Mach-O is killed by the device with SIGKILL before main() --
# no output, no crash report -- which is the documented failure mode that
# the old "ldid -S ... || true" used to ship silently.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst" || { echo "cp failed: $src -> $dst" >&2; exit 1; }
    command -v ldid >/dev/null 2>&1 || {
        echo "ldid is not on PATH -- refusing to package an unsigned binary" >&2
        exit 1
    }
    ldid -S "$dst" || { echo "ldid -S failed for $dst" >&2; exit 1; }
    ldid -e "$dst" >/dev/null 2>&1 || {
        echo "$dst carries no signature after ldid -S" >&2
        exit 1
    }
}

bin="$OUT/lsof-$LSOF_VERSION-armv7"
[ -f "$bin" ] || {
    echo "missing $bin -- rerun lsof/build.sh" >&2
    exit 1
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools" "$w/usr/share/doc/lsof"

cat > "$w/DEBIAN/control" <<CTRL
Package: lsof
Name: lsof $LSOF_VERSION
Version: $LSOF_VERSION-$DEBREV
Section: Utilities
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://github.com/lsof-org/lsof
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: lsof (LiSt Open Files) for armv7 iOS 10+
 lsof $LSOF_VERSION, cross-compiled for armv7 iOS 10.x.  The libproc-based
 Darwin dialect: enumerates processes and their open files through
 proc_listpids()/proc_pidinfo(), the same kernel interface ps uses.
 .
 Installs /var/mobile/tools/lsof.  Run it as root (sudo) to see other
 users' processes; unprivileged runs only show your own -- the same
 behaviour as on macOS, where lsof is also privileged.
 .
 Replaces the 2013 lsof 4.78 found in jailbreak images, which fails on
 iOS 10 with "Cannot allocate memory" for every PID because its
 hand-parsed struct kinfo_proc no longer matches the kernel.
CTRL

cat > "$w/usr/share/doc/lsof/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: lsof
Source: https://github.com/lsof-org/lsof/archive/refs/tags/$LSOF_VERSION.tar.gz

Files: *
Copyright: 1994-2026 Purdue Research Foundation, Victor A. Abell, and
 the lsof-org maintainers
License: lsof
 The lsof copyright (see the COPYING file in the source distribution):
 permission to use, copy, modify and distribute this software and its
 documentation for any purpose and without fee is granted, provided the
 copyright notices appear in supporting documentation; the copyright
 holders make no representations about the suitability of this software
 for any purpose.  Portions copyright the Regents of the University of
 California and Apple Inc. per the headers in the source.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: lsof

Cross-compiled for armv7 iOS 10.x.  sys/proc_info.h in the build sysroot is
copied verbatim from the xnu source tag matching iOS 10.3.x; see
sysroot-overlay/usr/include/sys/proc_info.h.
CR

sign "$bin" "$w/var/mobile/tools/lsof"
chmod 0755 "$w/var/mobile/tools/lsof"

deb="$OUT/lsof_${LSOF_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device:"
echo "      dpkg -i $deb"
