#!/bin/bash
# Package socat as socat4_<ver>_iphoneos-arm.deb.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
VER="${SOCAT_VERSION:-1.8.0.3}"
BIN="$OUT/socat4-armv7"
[ -f "$BIN" ] || { echo "missing $BIN (run socat/build.sh)" >&2; exit 1; }
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/bin" "$w/var/mobile/tools/socat" "$w/usr/share/doc/socat4"
cat > "$w/DEBIAN/control" <<CTRL
Package: socat4
Name: socat
Version: $VER-1
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: Hesper <hesperup@users.noreply.github.com>
Homepage: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: socat 1.8.0.3 multipurpose relay for armv7 iOS 10+
 TCP/UDP/UNIX/EXEC bidirectional relay — the network Swiss army knife
 (port forwarding, pipes, testing).  Runs as mobile; privileged
 operations (low ports) need root.
CTRL
cat > "$w/DEBIAN/postinst" <<POST
#!/bin/sh
set -e
if command -v ldid >/dev/null 2>&1; then
    ldid -S /var/mobile/tools/socat/socat 2>/dev/null || true
fi
chown mobile:mobile /var/mobile/tools/socat/socat 2>/dev/null || true
chmod 0755 /var/mobile/tools/socat/socat 2>/dev/null || true
ln -sf /var/mobile/tools/socat/socat /usr/bin/socat
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"
cat > "$w/DEBIAN/prerm" <<PRERM
#!/bin/sh
set -e
rm -f /usr/bin/socat
exit 0
PRERM
chmod 0755 "$w/DEBIAN/prerm"
install -m 0755 "$BIN" "$w/var/mobile/tools/socat/socat"
cat > "$w/usr/share/doc/socat4/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: socat
Source: http://www.dest-unreach.org/socat/ (GPL-2+)

Files: *
Copyright: 1996-2025 Gerhard Rieger
License: GPL-2+
COPYRIGHT
dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/socat4_${VER}-1_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT
echo "==> $OUT/socat4_${VER}-1_iphoneos-arm.deb"
sha256sum "$OUT/socat4_${VER}-1_iphoneos-arm.deb"
