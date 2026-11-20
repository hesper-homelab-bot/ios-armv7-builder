#!/bin/bash
# Package iperf3 as iperf34_<ver>_iphoneos-arm.deb.
# Installs to /var/mobile/tools/iperf3 + /usr/bin link (no setuid needed:
# iperf3 server/client use ordinary TCP/UDP sockets).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
VER="${IPERF3_VERSION:-3.22.1}"
BIN="$OUT/iperf34-armv7"
[ -f "$BIN" ] || { echo "missing $BIN (run iperf3/build.sh)" >&2; exit 1; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/bin" "$w/var/mobile/tools/iperf3" \
         "$w/usr/share/doc/iperf34"

cat > "$w/DEBIAN/control" <<CTRL
Package: iperf34
Name: iperf3 $VER
Version: $VER-1
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: Hesper <hesperup@users.noreply.github.com>
Homepage: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: iperf3 3.22.1 for armv7 iOS 10+ (WiFi throughput testing)
 Client/server bandwidth measurement.  Server runs fine as mobile (ordinary
 TCP/UDP sockets); pair with a host-side iperf3 over WiFi.
CTRL

cat > "$w/DEBIAN/postinst" <<POST
#!/bin/sh
set -e
if command -v ldid >/dev/null 2>&1; then
    ldid -S /var/mobile/tools/iperf3/iperf3 2>/dev/null || true
fi
chown mobile:mobile /var/mobile/tools/iperf3/iperf3 2>/dev/null || true
chmod 0755 /var/mobile/tools/iperf3/iperf3 2>/dev/null || true
ln -sf /var/mobile/tools/iperf3/iperf3 /usr/bin/iperf3
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"

cat > "$w/DEBIAN/prerm" <<PRERM
#!/bin/sh
set -e
rm -f /usr/bin/iperf3
exit 0
PRERM
chmod 0755 "$w/DEBIAN/prerm"

install -m 0755 "$BIN" "$w/var/mobile/tools/iperf3/iperf3"
cat > "$w/usr/share/doc/iperf34/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: iperf
Source: https://github.com/esnet/iperf (BSD-3-Clause)

Files: *
Copyright: 2014-2024 ESnet
License: BSD-3-Clause
COPYRIGHT

dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/iperf34_${VER}-1_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT
echo "==> $OUT/iperf34_${VER}-1_iphoneos-arm.deb"
sha256sum "$OUT/iperf34_${VER}-1_iphoneos-arm.deb"
