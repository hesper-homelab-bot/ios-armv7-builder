#!/bin/bash
# Package the armv7 wget build into a .deb for the APT repo.
#
# Follows ../curl/make-deb.sh exactly: the package installs under
# /var/mobile/tools so nothing in /usr is touched, and uninstalling is just
# `rm -rf /var/mobile/tools/wget`.  wget has no shared-library dependency --
# it links libcrypto.a and libssl.a statically -- so no Depends beyond
# firmware, unlike curl4 which pulls openssl4 for its binaries.
#
# Usage:
#   ./wget/make-deb.sh                 # uses ../out/wget-*-armv7
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
WGET_VERSION="${WGET_VERSION:-1.25.0}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"

WGET_BIN="$OUT/wget-$WGET_VERSION-armv7"
[ -f "$WGET_BIN" ] || { echo "missing $WGET_BIN (run wget/build.sh)" >&2; exit 1; }

# Host ldid occasionally produces a binary the device kills with "Killed: 9"
# and no crash report; signing on the device always works.  The packaging
# scripts therefore sign twice, exactly as curl/make-deb.sh does.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    ldid -S "$dst" 2>/dev/null || true
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools" "$w/usr/share/doc/wget4"
cat > "$w/DEBIAN/control" <<CTRL
Package: wget4
Name: GNU Wget 1.25
Version: $WGET_VERSION-$DEBREV
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://www.gnu.org/software/wget/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: GNU wget for armv7 iOS 10+ (static OpenSSL 4)
 GNU wget $WGET_VERSION for armv7 iOS 10.x, statically linked against
 OpenSSL 4.0.3.  Installs to /var/mobile/tools/wget, so it does not
 replace the system binary that sshd and the rest of iOS may expect.
 .
 Working: HTTP, HTTPS, FTP (anonymous), cookies, redirects, POST,
 --spider, --limit-rate, recursive retrieval.  Add /var/mobile/tools to
 your PATH, or call it by absolute path.
 .
 Set SSL_CERT_FILE=/etc/ssl/cert.pem to verify HTTPS certificates; see
 /var/mobile/tools/env.sh.
CTRL

cat > "$w/usr/share/doc/wget4/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: wget
Source: https://ftp.gnu.org/gnu/wget/wget-$WGET_VERSION.tar.gz

Files: *
Copyright: 1996-2026 Free Software Foundation, Inc.
License: GPL-3.0+
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 .
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: GPL-3.0+

Cross-compiled for armv7 iOS 10.x.  The sysroot headers used to build it are
original clean-room stubs or BSD-licensed musl headers; no Apple SDK files
are redistributed.
CR

# A convenience file users can source, mirroring what curl4 documents.
cat > "$w/var/mobile/tools/env.sh" <<'ENV'
# Source this (or add /var/mobile/tools to PATH) to use wget4/curl4.
export PATH=/var/mobile/tools:$PATH
export SSL_CERT_FILE=/etc/ssl/cert.pem
ENV
chmod 0755 "$w/var/mobile/tools/env.sh"

sign "$WGET_BIN" "$w/var/mobile/tools/wget"
chmod 0755 "$w/var/mobile/tools/wget"
deb="$OUT/wget4_${WGET_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device:"
echo "      cp $deb /var/mobile/ && dpkg -i $deb"
