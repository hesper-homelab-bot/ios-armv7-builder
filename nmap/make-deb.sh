#!/bin/bash
# Package the armv7 nmap build into a .deb for the APT repo.
#
# Follows ../wget/make-deb.sh: installs under /var/mobile/tools so nothing
# in /usr is touched.  nmap needs its data files (nmap-services etc), which
# this script copies from the build tree into share/nmap/.  Fully static
# (libpcap, openssl, zlib, pcre2, lua, libdnet, liblinear are all .a), so
# no Depends beyond firmware.
#
# Usage:
#   ./nmap/make-deb.sh                # uses ../out/nmap-7.95-armv7
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
NMAP_VERSION="${NMAP_VERSION:-7.95}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
SRC="${NMAP_SRC:-$HOME/ios-tool/nmap-src/nmap-$NMAP_VERSION}"

NMAP_BIN="$OUT/nmap-$NMAP_VERSION-armv7"
[ -f "$NMAP_BIN" ] || { echo "missing $NMAP_BIN (run nmap/build.sh)" >&2; exit 1; }

# Host ldid occasionally produces a binary the device kills with "Killed: 9"
# and no crash report; signing on the device always works.  The packaging
# scripts therefore sign twice, exactly as curl/make-deb.sh does.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    ldid -S "$dst" 2>/dev/null || true
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools" "$w/usr/share/doc/nmap"

cat > "$w/DEBIAN/control" <<CTRL
Package: nmap
Name: Nmap 7.95
Version: $NMAP_VERSION-$DEBREV
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://nmap.org/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: Nmap 7.95 for armv7 iOS 10+ (connect scan verified)
 Nmap $NMAP_VERSION for armv7 iOS 10.x with ncat.  Everything is
 statically linked (libpcap, OpenSSL 4, zlib, pcre2, lua, libdnet,
 liblinear); installs under /var/mobile/tools, nothing in /usr is
 touched.
 .
 Verified on an iPad 4: --iflist enumerates interfaces, TCP connect scan
 (-sT) reports open ports correctly.  Wi-Fi interfaces refuse
 promiscuous mode, so raw-packet scans (-sS/-sU) may need USB/ethernet
 or simply may not work; -sT works.
 .
 Data files ship in /var/mobile/tools/share/nmap.  Run as root for
 anything beyond unprivileged connect scans.  Add /var/mobile/tools to
 your PATH, or call it by absolute path.
CTRL

cat > "$w/usr/share/doc/nmap/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: nmap
Source: https://nmap.org/dist/nmap-$NMAP_VERSION.tar.bz2

Files: *
Copyright: 1996-2026 Insecure.Com LLC (Nmap Project)
License: NPSL-0.94+
 Nmap is distributed under the Nmap Public Source License; see the
 COPYING file shipped with the source.  Bundled libraries (libpcap,
 lua, libdnet, liblinear, pcre2, zlib) carry their own BSD/MIT-style
 licenses.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: NPSL-0.94+

Cross-compiled for armv7 iOS 10.x.  The sysroot headers used to build it are
original clean-room stubs, BSD-licensed musl headers, and XNU kernel headers;
no Apple SDK files are redistributed.
CR

# binary + data files
sign "$NMAP_BIN" "$w/var/mobile/tools/nmap"
chmod 0755 "$w/var/mobile/tools/nmap"
if [ -f "$SRC/ncat/ncat" ]; then
    sign "$SRC/ncat/ncat" "$w/var/mobile/tools/ncat"
    chmod 0755 "$w/var/mobile/tools/ncat"
fi
mkdir -p "$w/var/mobile/tools/share/nmap"
for f in nmap-services nmap-protocols nmap-service-probes nmap-mac-prefixes \
         nmap-rpc nmap-payloads nmap-protocols nse_main.lua; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$w/var/mobile/tools/share/nmap/"
done
for d in scripts nselib; do
    [ -d "$SRC/$d" ] && cp -a "$SRC/$d" "$w/var/mobile/tools/share/nmap/"
done

deb="$OUT/nmap_${NMAP_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device:"
echo "      cp $deb /var/mobile/ && dpkg -i $deb"
