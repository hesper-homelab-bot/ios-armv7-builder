#!/bin/bash
# make-deb.sh -- build whois4 deb for armv7 iOS 10.3.3
#
# Payload layout (p7zip17 pattern):
#   /var/mobile/tools/whois/whois   the real binary (root:wheel, host-signed)
#   /var/mobile/tools/bin/whois     symlink (login shells)
# Data (tld_serv etc.) is compiled into the binary -- nothing else to ship.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
UPSTREAM="$(ls "$REPO_OUT"/whois-*-armv7 2>/dev/null | sed "s|.*/whois-\(.*\)-armv7|\1|" | head -1)"
VERSION="$UPSTREAM-1"
BIN_SRC="$REPO_OUT/whois-$UPSTREAM-armv7" # build.sh 产物（未签名）
DEB="$REPO_OUT/whois4_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/whois4-stage"

[ -f "$BIN_SRC" ] || { echo "missing $BIN_SRC -- run build.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE/var/mobile/tools/whois" \
         "$STAGE/var/mobile/tools/bin" \
         "$STAGE/DEBIAN"

cp "$BIN_SRC" "$STAGE/var/mobile/tools/whois/whois"
chmod 755 "$STAGE/var/mobile/tools/whois/whois"
ldid -S "$STAGE/var/mobile/tools/whois/whois"
ldid -e "$STAGE/var/mobile/tools/whois/whois" >/dev/null

ln -sf /var/mobile/tools/whois/whois "$STAGE/var/mobile/tools/bin/whois"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: whois4
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: whois 5.6.6 (rfc1036) for iOS 10.3.3 armv7
 RIPE-style whois client; server list compiled in.  Built without
 iconv/libidn/NLS (see whois/build.sh).
Section: net
Priority: optional
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN="/var/mobile/tools/whois/whois"
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ -L "/var/mobile/tools/bin/whois" ] && rm -f "/var/mobile/tools/bin/whois" || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -8
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
