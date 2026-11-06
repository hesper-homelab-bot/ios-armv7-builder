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
# Second -p handed to the dropbear binary as a fallback listener.  Empty for a
# single-port install; DROPBEAR_EXTRA_ARGS="" is honoured, so unset it to drop
# the fallback rather than passing a stray empty argument.
EXTRA_ARGS="${DROPBEAR_EXTRA_ARGS--p 2222}"

# Host ldid occasionally produces a binary the device kills with "Killed: 9"
# and no crash report; signing on the device always works.  So sign twice,
# exactly as the other packaging scripts do.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    ldid -S "$dst" 2>/dev/null || true
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

install -m 0755 "$here/dropbear-daemon.sh" "$w/var/mobile/.local/bin/dropbear-daemon.sh"

for p in dropbear dbclient dropbearkey scp; do
    bin="$OUT/dropbear-$p-$DB_VERSION-armv7"
    [ -f "$bin" ] || { echo "missing $bin (run dropbear/build.sh)" >&2; exit 1; }
    sign "$bin" "$w/var/mobile/tools/db-$p"
    chmod 0755 "$w/var/mobile/tools/db-$p"
done

deb="$OUT/dropbear4_${DB_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device:"
echo "      dpkg -i $deb"
