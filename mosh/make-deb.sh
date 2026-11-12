#!/bin/bash
# Package the armv7 mosh build into a .deb for the APT repo.
#
# mosh is unusual: the interesting binary on the DEVICE is mosh-server
# (the Mac side runs the client).  mosh-client is shipped too (self-test /
# iOS-side loopback).  The `mosh` launcher script needs perl, which the
# device does not have -- it lives on the client machine only.
#
# Install (client side, e.g. macOS with brew mosh):
#   mosh --server="/var/mobile/tools/bin/mosh-server new" mobile@<device>
# or create a symlink once on the device:
#   ln -s /var/mobile/tools/bin/mosh-server /usr/local/bin/mosh-server
# and then plain `mosh mobile@<device>` works.
#
# Usage:
#   ./mosh/make-deb.sh                # uses ../out/mosh-{server,client}
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
MOSH_VERSION="${MOSH_VERSION:-1.4.0}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"

SERVER_BIN="$OUT/mosh-server"
CLIENT_BIN="$OUT/mosh-client"
[ -f "$SERVER_BIN" ] && [ -f "$CLIENT_BIN" ] || { echo "missing $SERVER_BIN/$CLIENT_BIN (run mosh/build.sh)" >&2; exit 1; }

# Host ldid occasionally produces a binary the device kills with "Killed: 9"
# and no crash report; signing on the device always works.  The packaging
# scripts therefore sign twice, exactly as curl/make-deb.sh does.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    ldid -S "$dst" 2>/dev/null || true
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools/bin" "$w/usr/share/doc/mosh"

cat > "$w/DEBIAN/control" <<CTRL
Package: mosh
Name: Mosh 1.4
Version: $MOSH_VERSION-$DEBREV
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://mosh.org/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: Mosh 1.4.0 for armv7 iOS 10+ (roaming SSH, UDP 60000-61000)
 Mosh 1.4.0 for armv7 iOS 10.x: mosh-server + mosh-client, statically
 linked against libprotobuf 3.20.3 and OpenSSL 4.  Installs under
 /var/mobile/tools; nothing in /usr is touched.
 .
 mosh survives roaming, suspend and IP changes over UDP 60000-61000 --
 the point of having it on a tablet that switches networks.  Run from a
 client machine:
   mosh --server="/var/mobile/tools/bin/mosh-server new" mobile@<device>
 (the `mosh` launcher itself is a perl script; iOS has no perl, so the
 --server= form or a /usr/local/bin symlink is required).
 .
 The device has no locale support; this build treats the missing locale
 as UTF-8 (probe-verified; mosh never transcodes server-side).
CTRL

cat > "$w/usr/share/doc/mosh/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: mosh
Source: https://github.com/mobile-shell/mosh/releases

Files: *
Copyright: 2012-2026 Keith Winstein and the mosh developers
License: GPL-3.0+
 mosh is distributed under the GNU General Public License v3; see the
 COPYING file shipped with the source.  Bundled protobuf is BSD-style.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: GPL-3.0+

Cross-compiled for armv7 iOS 10.x against libprotobuf 3.20.3 built from the
same toolchain.  The sysroot headers used to build it are original
clean-room stubs, BSD-licensed musl headers, and XNU kernel headers; no
Apple SDK files are redistributed.
CR

sign "$SERVER_BIN" "$w/var/mobile/tools/bin/mosh-server"
sign "$CLIENT_BIN" "$w/var/mobile/tools/bin/mosh-client"
chmod 0755 "$w/var/mobile/tools/bin/mosh-server" "$w/var/mobile/tools/bin/mosh-client"

deb="$OUT/mosh_${MOSH_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device:"
echo "      cp $deb /var/mobile/ && dpkg -i $deb"
echo "    connect from a client machine:"
echo "      mosh --server=\"/var/mobile/tools/bin/mosh-server new\" mobile@<device>"
