#!/bin/bash
# Package ifconfig + route as ifconfig4_<ver>_iphoneos-arm.deb.
#
# Installs the real network_cmds-457 tools to /var/mobile/tools/ifconfig/
# with /usr/bin symlinks (same pattern as rsync 3.3.0-2).  Root:wheel 0755,
# NO setuid: interface ioctls (SIOCAIFADDR/SIOCDIFADDR) and route
# add/delete need root, and a setuid ifconfig would hand the mobile user
# full interface control (en0 down = connectivity gone).  Read-only status
# (ifconfig -a / en0, route -n get) works as mobile; write ops run as root
# (ssh root@<device>).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
VER="${IFCONFIG_VERSION:-457}"
BIN_IFC="$OUT/ifconfig-armv7"
BIN_RTE="$OUT/route-armv7"
BIN_ARP="$OUT/arp-armv7"
BIN_NDP="$OUT/ndp-armv7"
[ -f "$BIN_IFC" ] || { echo "missing $BIN_IFC (run ifconfig/build.sh)" >&2; exit 1; }
[ -f "$BIN_RTE" ] || { echo "missing $BIN_RTE (run ifconfig/build.sh)" >&2; exit 1; }
[ -f "$BIN_ARP" ] || { echo "missing $BIN_ARP (run ifconfig/build.sh)" >&2; exit 1; }
[ -f "$BIN_NDP" ] || { echo "missing $BIN_NDP (run ifconfig/build.sh)" >&2; exit 1; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/bin" "$w/var/mobile/tools/ifconfig" \
         "$w/usr/share/doc/ifconfig4"

cat > "$w/DEBIAN/control" <<CTRL
Package: ifconfig4
Name: ifconfig + route (network_cmds-457)
Version: $VER-2
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: Hesper <hesperup@users.noreply.github.com>
Homepage: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: BSD ifconfig/route/arp/ndp for armv7 iOS 10+ (network_cmds-457)
 Real Apple network_cmds-457 (Darwin 16 / xnu-3789 era) ifconfig, route, arp and\n ndp,
 cross-built with -DPRIVATE against xnu-3789.70.16 kernel headers.  ifconfig
 does link/media/IPv4/IPv6 status and (as root) address alias add/delete;
 route does get/add/delete/flush/monitor via the routing socket.  Read-only
 status works as mobile; write ops need root.  No setuid on purpose.
CTRL

cat > "$w/DEBIAN/postinst" <<POST
#!/bin/sh
set -e
for b in ifconfig route arp ndp; do
    if command -v ldid >/dev/null 2>&1; then
        ldid -S /var/mobile/tools/ifconfig/\$b 2>/dev/null || true
    fi
    chown root:wheel /var/mobile/tools/ifconfig/\$b 2>/dev/null || true
    chmod 0755 /var/mobile/tools/ifconfig/\$b 2>/dev/null || true
    ln -sf /var/mobile/tools/ifconfig/\$b /usr/bin/\$b
done
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"

cat > "$w/DEBIAN/prerm" <<PRERM
#!/bin/sh
set -e
rm -f /usr/bin/ifconfig /usr/bin/route
exit 0
PRERM
chmod 0755 "$w/DEBIAN/prerm"

# no -o/-g: host cannot chown to root; --root-owner-group sets it in the deb
install -m 0755 "$BIN_IFC" "$w/var/mobile/tools/ifconfig/ifconfig"
install -m 0755 "$BIN_RTE" "$w/var/mobile/tools/ifconfig/route"
install -m 0755 "$BIN_ARP" "$w/var/mobile/tools/ifconfig/arp"
install -m 0755 "$BIN_NDP" "$w/var/mobile/tools/ifconfig/ndp"
cat > "$w/usr/share/doc/ifconfig4/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: network_cmds (ifconfig.tproj, route.tproj)
Source: https://github.com/apple-oss-distributions/network_cmds
        tag network_cmds-457 (APSL 2.0; full text in APPLE_LICENSE at
        https://github.com/apple-oss-distributions/network_cmds/blob/
        network_cmds-457/APPLE_LICENSE)

Files: *
Copyright: 2000-2016 Apple Inc.; 1995-1998 WIDE Project; BSD contributors
License: APSL-2.0
COPYRIGHT

dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/ifconfig4_${VER}-2_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT
echo "==> $OUT/ifconfig4_${VER}-2_iphoneos-arm.deb"
sha256sum "$OUT/ifconfig4_${VER}-2_iphoneos-arm.deb"
