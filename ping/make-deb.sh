#!/bin/bash
# Package ping as ping4_<ver>-1_iphoneos-arm.deb.
# ping installs setuid root (4755): mobile users need it, and ICMP echo
# requires SOCK_RAW (probed: the unprivileged SOCK_DGRAM form sends but iOS
# 10 never delivers echo replies to it).  postinst re-signs via device ldid
# (sign the payload, keep the setuid bit).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
VER="${PING_VERSION:-1.0}"
BIN="$OUT/ping-armv7"
[ -f "$BIN" ] || { echo "missing $BIN (run ping/build.sh)" >&2; exit 1; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/bin" "$w/usr/share/doc/ping4"

cat > "$w/DEBIAN/control" <<CTRL
Package: ping4
Name: ping $VER
Version: $VER-1
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: Hesper <hesperup@users.noreply.github.com>
Homepage: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: minimal ICMP ping for armv7 iOS 10+ (setuid, SOCK_RAW)
 Self-contained ICMP echo ping.  Installs setuid root (4755) because iOS
 10 delivers ICMP echo replies only to sockets opened with SOCK_RAW,
 which needs root; the unprivileged SOCK_DGRAM form sends but receives
 nothing (device-probed).  Supports -c count -i interval -s size -W ms.
CTRL

cat > "$w/DEBIAN/postinst" <<POST
#!/bin/sh
set -e
if command -v ldid >/dev/null 2>&1; then
    ldid -S /usr/bin/ping 2>/dev/null || true
fi
chown root:wheel /usr/bin/ping 2>/dev/null || true
chmod 4755 /usr/bin/ping 2>/dev/null || true
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"

install -m 4755 "$BIN" "$w/usr/bin/ping"
cat > "$w/usr/share/doc/ping4/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ping
Source: hand-written for ios-armv7-builder (no upstream; see ping.c header)

Files: *
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: MIT
COPYRIGHT

dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/ping4_${VER}-1_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT
echo "==> $OUT/ping4_${VER}-1_iphoneos-arm.deb"
sha256sum "$OUT/ping4_${VER}-1_iphoneos-arm.deb"
