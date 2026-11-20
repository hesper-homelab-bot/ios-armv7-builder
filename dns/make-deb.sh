#!/bin/bash
# Package dnsq as dns4_<ver>_iphoneos-arm.deb.
# One binary, three names (dig/nslookup/host) via argv[0] dispatch +
# /usr/bin links (rsync/smalltools precedent).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
VER="${DNS_VERSION:-1.0}"
BIN="$OUT/dnsq-armv7"
[ -f "$BIN" ] || { echo "missing $BIN (run dns/build.sh)" >&2; exit 1; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/bin" "$w/var/mobile/tools/dns" \
         "$w/usr/share/doc/dns4"

cat > "$w/DEBIAN/control" <<CTRL
Package: dns4
Name: dig nslookup host
Version: $VER-1
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: Hesper <hesperup@users.noreply.github.com>
Homepage: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: dig/nslookup/host for armv7 iOS 10+ (self-contained stub resolver)
 The DNS clients the device ships zero of, one binary dispatched by argv[0]:
 dig (@server, types, +short), nslookup and host, over UDP with retries and
 TCP fallback on truncation.  Resolver comes from /etc/resolv.conf.
CTRL

cat > "$w/DEBIAN/postinst" <<POST
#!/bin/sh
set -e
for n in dig nslookup host; do
    ln -sf dnsq /var/mobile/tools/dns/\$n
    ln -sf /var/mobile/tools/dns/\$n /usr/bin/\$n
done
if command -v ldid >/dev/null 2>&1; then
    ldid -S /var/mobile/tools/dns/dnsq 2>/dev/null || true
fi
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"

cat > "$w/DEBIAN/prerm" <<PRERM
#!/bin/sh
set -e
for n in dig nslookup host; do
    rm -f /usr/bin/\$n
done
exit 0
PRERM
chmod 0755 "$w/DEBIAN/prerm"

install -m 0755 "$BIN" "$w/var/mobile/tools/dns/dnsq"
cat > "$w/usr/share/doc/dns4/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: dnsq
Source: hand-written for ios-armv7-builder (no upstream)

Files: *
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: MIT
COPYRIGHT

dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/dns4_${VER}-1_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT
echo "==> $OUT/dns4_${VER}-1_iphoneos-arm.deb"
sha256sum "$OUT/dns4_${VER}-1_iphoneos-arm.deb"
