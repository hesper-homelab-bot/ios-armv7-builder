#!/bin/bash
# make-deb.sh -- build netstat4 deb for armv7 iOS 10.3.3
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/out"
DEB="$OUT/netstat4_1.0-1_iphoneos-arm.deb"
STAGE="$OUT/netstat4-stage"
BINDIR="$STAGE/var/mobile/tools/bin"

rm -rf "$STAGE" "$DEB"
mkdir -p "$BINDIR"

# copy signed binary from scratch
cp ~/scratch/netstat/netstat "$BINDIR/netstat"
chmod 755 "$BINDIR/netstat"
# sign is already done, but re-assert
ldid -S "$BINDIR/netstat"

# control file
mkdir -p "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: netstat4
Version: 1.0-1
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: netstat for iOS 10.3.3 armv7
 Shows active Internet connections, routing tables, and interface statistics.
 Built from device-verified ABI (xinpgen/xinpcb/xtcpcb offsets measured on
 xnu-3789.70.16). Supports -a -t -u -r -i flags, numeric output.
Section: net
Priority: optional
EOF

# postinst: nothing special, just ensure ldid signature
cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN="/var/mobile/tools/bin/netstat"
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1 || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

# prerm: nothing
cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

# build deb
# -Zgzip: 设备 dpkg 1.18.10 不认 zstd 成员（control.tar.zst 报
#   "unknown compression"，2026-11-14 设备实测）；--root-owner-group 与
#   lsof/make-deb.sh 同款，载荷归 root:root。
dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB"
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"

# copy to repo staging (scripts/make-repo.sh scans the REPO-root out/)
cp "$DEB" "$ROOT/../out/"