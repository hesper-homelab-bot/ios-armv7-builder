#!/bin/bash
# Package the armv7 Dropbear build into a .deb for the APT repo.
#
# Mirrors ../curl/make-deb.sh and ../wget/make-deb.sh: everything installs
# under /var/mobile so removing the package leaves the device as it was, and
# nothing in /usr is touched.
#
# What is installed:
#   /var/mobile/tools/db-{dropbear,dbclient,dropbearkey,scp}
#       the binaries, kept prefixed with db- so they never shadow the system
#       ssh/scp that the OS and sshd depend on
#   /var/mobile/.local/bin/dropbear-daemon.sh
#       the wrapper: generates host keys on first run and execs dropbear -F
#   /Library/LaunchDaemons/com.hesper.dropbear.plist
#       the daemon, on the primary port with a fallback, with KeepAlive
#
# INSTALL LAYOUT: dropbear takes over port 22 and keeps the port it was
# installed and verified on (2222) as a fallback.  The legacy /usr/sbin/sshd
# is moved to 22222 by sshfix rather than removed, so uninstalling this
# package and reverting the plists restores the original access path.
#
# Usage:
#   ./dropbear/make-deb.sh                 # uses ../out/dropbear-*-armv7
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
DB_VERSION="${DB_VERSION:-2026.94}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
PORT="${DROPBEAR_PORT:-22}"

# Where the .deb lands.  A build with default parameters goes to out/, which is
# what scripts/make-repo.sh scans and what releases are cut from.  A build with
# any non-default option -- another port, a fallback -p, the custom sftp-server
# -- is for one specific device, and publishing it would hand everybody a
# package tuned for someone else's setup, so it goes to pkg/ instead.
CUSTOM=0
[ "$PORT" = "22" ]        || CUSTOM=1
[ -n "$EXTRA_ARGS" ]      || CUSTOM=1
[ "${WITH_DB_SFTPSERVER:-0}" = "1" ] && CUSTOM=1
if [ "$CUSTOM" = 1 ]; then OUTDIR="$root/pkg"; else OUTDIR="$root/out"; fi
mkdir -p "$OUTDIR"
# An extra -p handed to the dropbear binary as a fallback listener.  Empty by
# default: the 2222 lifeline this used to carry is gone now that
# com.hesper.osshd serves OpenSSH 10.6p2 on 22226.  Note the ${VAR-...} form
# with a single dash -- "${VAR:-...}" would substitute the fallback for an
# explicitly empty value too, which is the opposite of what we want here.
EXTRA_ARGS="${DROPBEAR_EXTRA_ARGS-}"

# Host ldid occasionally produces a binary the device kills with "Killed: 9"
# and no crash report; signing on the device always works.  So sign twice,
# exactly as the other packaging scripts do.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst" || { echo "cp failed: $src -> $dst" >&2; exit 1; }

    # Failures here must be loud.  This function used to end in
    #     ldid -S "$dst" 2>/dev/null || true
    # which swallowed everything, and the binary that reached the package was
    # then *unsigned* -- and an unsigned Mach-O is killed by the device with
    # SIGKILL and no crash report, before main().  That is the whole origin of
    # the "host ldid occasionally produces a binary the device kills with
    # Killed: 9" folklore: not host ldid being unreliable, but this
    # swallowing the failure.  See the signing section in README.
    command -v ldid >/dev/null 2>&1 || {
        echo "ldid is not on PATH -- refusing to package an unsigned binary" >&2
        exit 1
    }
    ldid -S "$dst" || {
        echo "ldid -S failed for $dst" >&2
        exit 1
    }

    # ldid -e exits 0 only when the file actually carries a signature (verified
    # by signing a copy of an unsigned binary and re-checking), so this is a
    # real assertion rather than a formality.
    ldid -e "$dst" >/dev/null 2>&1 || {
        echo "$dst carries no signature after ldid -S" >&2
        exit 1
    }
}


w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools" "$w/var/mobile/.local/bin" \
         "$w/Library/LaunchDaemons" "$w/usr/share/doc/dropbear4"

cat > "$w/DEBIAN/control" <<CTRL
Package: dropbear4
Name: Dropbear SSH $DB_VERSION
Version: $DB_VERSION-$DEBREV
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://matt.ucc.asn.au/dropbear/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: Dropbear SSH server and client for armv7 iOS 10+ (port $PORT)
 Dropbear $DB_VERSION, cross-compiled for armv7 iOS 10.x with its bundled
 libtomcrypt (no OpenSSL dependency).
 .
 Installs /var/mobile/tools/db-dropbear (server), db-dbclient, db-dropbearkey
 and db-scp, plus a LaunchDaemon that runs the server on port $PORT${EXTRA_ARGS:+ with $EXTRA_ARGS as a fallback}.
 .
 This is the primary SSH server on port 22; the legacy /usr/sbin/sshd is
 relocated to port 22222 by sshfix, not deleted, so the previous access
 path is still recoverable if this package is removed.
CTRL

cat > "$w/usr/share/doc/dropbear4/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: dropbear
Source: https://matt.ucc.asn.au/dropbear/releases/dropbear-$DB_VERSION.tar.bz2

Files: *
Copyright: 2002-2026 Matt Johnston and contributors
License: MIT-style
 Permission to use, copy, modify, and distribute this software for any
 purpose with or without fee is hereby granted, provided that the above
 copyright notice and this permission notice appear in all copies.
 .
 Portions copyright other authors; see the LICENCE file in the source
 distribution.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: MIT-style

Cross-compiled for armv7 iOS 10.x.  The sysroot headers used to build it are
original clean-room stubs or BSD-licensed musl headers; no Apple SDK files
are redistributed.  The bundled libtomcrypt and libtommath are public domain.
CR

# The primary port and the fallback -p argument are substituted at package
# time, so a rebuild with DROPBEAR_PORT=... produces a matching package.
# The placeholders are delimited on purpose: a plain s|DROPBEAR_PORT|...|
# would also rewrite the *key name* DROPBEAR_PORT in the plist and break the
# environment dictionary.
sed -e "s|__DROPBEAR_PORT__|$PORT|" \
    -e "s|__DROPBEAR_EXTRA_ARGS__|$EXTRA_ARGS|" \
    "$here/dropbear-daemon.plist" \
    > "$w/Library/LaunchDaemons/com.hesper.dropbear.plist"
chmod 0644 "$w/Library/LaunchDaemons/com.hesper.dropbear.plist"

# A conffile, deliberately.  This plist carries the port, and a device with both
# SSH packages installed has to move one of them off 22.  Without the conffile
# declaration dpkg would overwrite that edit with the packaged default on every
# upgrade and put two daemons on one port -- the exact regression the wrapper's
# port check now reports instead of hiding.
echo "/Library/LaunchDaemons/com.hesper.dropbear.plist" > "$w/DEBIAN/conffiles"

install -m 0755 "$here/dropbear-daemon.sh" "$w/var/mobile/.local/bin/dropbear-daemon.sh"

# The SFTP server is opt-in, in both directions: build.sh only compiles it when
# WITH_DB_SFTPSERVER=1, and this package only ships it then too.  The default
# is deliberately not to have it -- see the WITH_DB_SFTPSERVER block in
# build.sh for why dropbear has no sftp server of its own.
BINS="dropbear dbclient dropbearkey scp"
if [ "${WITH_DB_SFTPSERVER:-0}" = "1" ]; then
    BINS="$BINS sftp-server"
fi
for p in $BINS; do
    bin="$OUT/dropbear-$p-$DB_VERSION-armv7"
    [ -f "$bin" ] || {
        echo "missing $bin -- rerun dropbear/build.sh${WITH_DB_SFTPSERVER:+ WITH_DB_SFTPSERVER=1}" >&2
        exit 1; }
    sign "$bin" "$w/var/mobile/tools/db-$p"
    chmod 0755 "$w/var/mobile/tools/db-$p"
done
# The shipped set is asserted rather than assumed, so a build that silently
# forgot the opt-in cannot ship a plist that points at a missing sftp-server.
[ "${WITH_DB_SFTPSERVER:-0}" = "1" ] || [ ! -e "$w/var/mobile/tools/db-sftp-server" ] || {
    echo "db-sftp-server present without WITH_DB_SFTPSERVER=1" >&2; exit 1; }

deb="$OUTDIR/dropbear4_${DB_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device:"
echo "      dpkg -i $deb"
