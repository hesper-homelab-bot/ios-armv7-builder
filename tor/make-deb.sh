#!/bin/bash
# make-deb.sh -- build tor4 deb for armv7 iOS 10.3.3
#
# Payload layout (p7zip17 pattern):
#   /var/mobile/tools/tor/tor       the real binary (root:wheel, host-signed)
#   /var/mobile/tools/bin/tor       symlink (login shells)
# Static: libevent 2.1.12 + OpenSSL 4.0.3 + zlib 1.3.1 (all in-tree linked
# from ~/ios-tool/build-ios/install & openssl-src prefixes).  No LZMA/ZSTD.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
UPSTREAM="0.4.8.14"                       # build.sh 产物命名（tor-<UPSTREAM>-armv7）
VERSION="$UPSTREAM-1"                     # deb 版本
BIN_SRC="$REPO_OUT/tor-$UPSTREAM-armv7"   # build.sh 产物（未签名）
DEB="$REPO_OUT/tor4_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/tor4-stage"

[ -f "$BIN_SRC" ] || { echo "missing $BIN_SRC -- run build.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE/var/mobile/tools/tor" \
         "$STAGE/var/mobile/tools/bin" \
         "$STAGE/DEBIAN"

cp "$BIN_SRC" "$STAGE/var/mobile/tools/tor/tor"
chmod 755 "$STAGE/var/mobile/tools/tor/tor"
ldid -S "$STAGE/var/mobile/tools/tor/tor"
ldid -e "$STAGE/var/mobile/tools/tor/tor" >/dev/null

ln -sf /var/mobile/tools/tor/tor "$STAGE/var/mobile/tools/bin/tor"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: tor4
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: tor 0.4.8.14 for iOS 10.3.3 armv7
 Onion router daemon.  Statically linked libevent 2.1.12 + OpenSSL 4.0.3 +
 zlib 1.3.1; no LZMA/ZSTD; dirauth module off.  DataDir defaults to
 /var/mobile/tools/tor/data -- set DataDir/SocksPort in your torrc.
Section: net
Priority: optional
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN="/var/mobile/tools/tor/tor"
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ -L "/var/mobile/tools/bin/tor" ] && rm -f "/var/mobile/tools/bin/tor" || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -8
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
