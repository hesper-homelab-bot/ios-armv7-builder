#!/bin/bash
# Package the armv7 tcpdump build into a .deb for the APT repo.
#
# Follows ../wget/make-deb.sh: installs under /var/mobile/tools so nothing
# in /usr is touched, uninstalling is just removing the binary.  Fully
# static (libpcap.a is linked in; no libcrypto by default), so no Depends
# beyond firmware.
#
# Packet capture needs root (BPF device access); the description says so.
#
# Usage:
#   ./tcpdump/make-deb.sh             # uses ../out/tcpdump-*-armv7
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
TD_VERSION="${TD_VERSION:-4.99.5}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"

TD_BIN="$OUT/tcpdump-$TD_VERSION-armv7"
[ -f "$TD_BIN" ] || { echo "missing $TD_BIN (run tcpdump/build.sh)" >&2; exit 1; }

# Host ldid occasionally produces a binary the device kills with "Killed: 9"
# and no crash report; signing on the device always works.  The packaging
# scripts therefore sign twice, exactly as curl/make-deb.sh does.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    ldid -S "$dst" 2>/dev/null || true
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools" "$w/usr/share/doc/tcpdump"
cat > "$w/DEBIAN/control" <<CTRL
Package: tcpdump
Name: tcpdump 4.99
Version: $TD_VERSION-$DEBREV
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://www.tcpdump.org/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: tcpdump 4.99.5 for armv7 iOS 10+ (BPF capture verified)
 tcpdump $TD_VERSION for armv7 iOS 10.x with live packet capture working
 over the device's /dev/bpf* devices.  Installs to /var/mobile/tools/tcpdump;
 nothing in /usr is touched.
 .
 Run as root to capture: /var/mobile/tools/tcpdump -i en0 -c 10 -n port 443.
 Wi-Fi interfaces refuse promiscuous mode (BIOCPROMISC is unsupported);
 tcpdump prints a warning and captures normally.
 .
 Add /var/mobile/tools to your PATH, or call it by absolute path.
CTRL

cat > "$w/usr/share/doc/tcpdump/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: tcpdump
Source: https://www.tcpdump.org/release/tcpdump-$TD_VERSION.tar.gz

Files: *
Copyright: 1988-2026 the tcpdump group (www.tcpdump.org)
License: BSD-3-clause
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the conditions in the LICENSE
 file shipped with the source are met (3-clause BSD).

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: BSD-3-clause

Cross-compiled for armv7 iOS 10.x against the bundled libpcap 1.10.5.
The sysroot headers used to build it are original clean-room stubs,
BSD-licensed musl headers, and XNU kernel headers (net/bpf.h); no Apple
SDK files are redistributed.
CR

sign "$TD_BIN" "$w/var/mobile/tools/tcpdump"
chmod 0755 "$w/var/mobile/tools/tcpdump"
deb="$OUT/tcpdump_${TD_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device:"
echo "      cp $deb /var/mobile/ && dpkg -i $deb"
