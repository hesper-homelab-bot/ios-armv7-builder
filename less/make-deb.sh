#!/bin/bash
# make-deb.sh -- build less4 deb for armv7 iOS 10.3.3
#
# Payload layout (p7zip17 pattern):
#   /var/mobile/tools/less/less     the real binary (root:wheel, host-signed)
#   /var/mobile/tools/bin/less      symlink (login shells)
# Runtime terminfo comes from the device's /usr/share/terminfo; curses is the
# device's own libncursesw.5.dylib (linked at build time -- see build.sh).
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
UPSTREAM="668"                            # build.sh 产物命名（less-<UPSTREAM>-armv7）
VERSION="$UPSTREAM-1"                     # deb 版本
BIN_SRC="$REPO_OUT/less-$UPSTREAM-armv7"  # build.sh 产物（未签名）
DEB="$REPO_OUT/less4_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/less4-stage"

[ -f "$BIN_SRC" ] || { echo "missing $BIN_SRC -- run build.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE/var/mobile/tools/less" \
         "$STAGE/var/mobile/tools/bin" \
         "$STAGE/DEBIAN"

cp "$BIN_SRC" "$STAGE/var/mobile/tools/less/less"
chmod 755 "$STAGE/var/mobile/tools/less/less"
ldid -S "$STAGE/var/mobile/tools/less/less"
ldid -e "$STAGE/var/mobile/tools/less/less" >/dev/null

ln -sf /var/mobile/tools/less/less "$STAGE/var/mobile/tools/bin/less"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: less4
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: less v668 for iOS 10.3.3 armv7
 Terminal pager.  Links the device's own libncursesw.5.dylib; terminfo from
 /usr/share/terminfo.  Built from the official less-668 release tarball
 (greenwoodsoftware.com).
Section: utils
Priority: optional
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN="/var/mobile/tools/less/less"
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ -L "/var/mobile/tools/bin/less" ] && rm -f "/var/mobile/tools/bin/less" || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -8
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
