#!/bin/bash
# Package traceroute as traceroute4_<ver>-1_iphoneos-arm.deb.
#
# traceroute installs setuid root (4755): it probes with SOCK_RAW
# (IPPROTO_UDP send + varying IP TTL, ICMP receive).  On iOS 10, SOCK_RAW
# creation requires root (same verdict as the ping port: unprivileged
# SOCK_DGRAM ICMP sends but never receives echo replies), so the mobile
# user needs the setuid bit.  Upstream Apple agrees: the pbxproj target
# "traceroute" sets ALTERNATE_MODE/INSTALL_MODE_FLAG = 04555, owner root,
# group wheel, INSTALL_PATH /usr/sbin.
#
# We install to /usr/bin/traceroute (mirroring the sibling ping4 deb; the
# device has no stock traceroute to collide with -- checked 2026-11-20).
# postinst re-signs via device ldid (sign the payload, keep the setuid bit).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
VER="${TRACEROUTE_VERSION:-1.0}"
BIN="$OUT/traceroute-armv7"
[ -f "$BIN" ] || { echo "missing $BIN (run traceroute/build.sh)" >&2; exit 1; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/bin" "$w/usr/share/doc/traceroute4"

cat > "$w/DEBIAN/control" <<CTRL
Package: traceroute4
Name: traceroute $VER
Version: $VER-1
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: Hesper <hesperup@users.noreply.github.com>
Homepage: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: traceroute for armv7 iOS 10+ (network_cmds-457, setuid, SOCK_RAW)
 Real Apple network_cmds-457 (Darwin 16 / xnu-3789 era) traceroute,
 cross-built with -DPRIVATE against xnu-3789.70.16 kernel headers.
 Installs setuid root (4755) because probing needs SOCK_RAW, which on
 iOS 10 requires root (the setuid root install shape is also Apple's own:
 pbxproj target "traceroute", mode 04555, root:wheel).  UDP/TCP/ICMP/GRE
 probe protocols, -n numeric, -q/-w/-m/-p knobs, AS lookup via -a.
CTRL

cat > "$w/DEBIAN/postinst" <<POST
#!/bin/sh
set -e
if command -v ldid >/dev/null 2>&1; then
    ldid -S /usr/bin/traceroute 2>/dev/null || true
fi
chown root:wheel /usr/bin/traceroute 2>/dev/null || true
chmod 4755 /usr/bin/traceroute 2>/dev/null || true
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"

install -m 4755 "$BIN" "$w/usr/bin/traceroute"
cat > "$w/usr/share/doc/traceroute4/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: network_cmds (traceroute.tproj)
Source: https://github.com/apple-oss-distributions/network_cmds
        tag network_cmds-457 (APSL 2.0; full text in APPLE_LICENSE at
        https://github.com/apple-oss-distributions/network_cmds/blob/
        network_cmds-457/APPLE_LICENSE)

Files: *
Copyright: 2004-2013 Apple Inc.; 1988-2000 The Regents of the University of California
License: APSL-2.0
COPYRIGHT

# gzip on purpose: the device dpkg (1.18.10) does not understand zst.
dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/traceroute4_${VER}-1_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT
echo "==> $OUT/traceroute4_${VER}-1_iphoneos-arm.deb"
sha256sum "$OUT/traceroute4_${VER}-1_iphoneos-arm.deb"