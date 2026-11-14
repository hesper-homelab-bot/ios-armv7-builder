#!/bin/bash
# make-deb.sh -- build make4 deb for armv7 iOS 10.3.3
#
# Payload layout (p7zip17 pattern):
#   /var/mobile/tools/make/make     the real binary (root:wheel, host-signed)
#   /var/mobile/tools/bin/make      symlink (login shells)
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
UPSTREAM="4.4.1"                          # build.sh 产物命名（make-<UPSTREAM>-armv7）
VERSION="$UPSTREAM-1"                     # deb 版本
BIN_SRC="$REPO_OUT/make-$UPSTREAM-armv7"  # build.sh 产物（未签名）
DEB="$REPO_OUT/make4_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/make4-stage"

[ -f "$BIN_SRC" ] || { echo "missing $BIN_SRC -- run build.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE/var/mobile/tools/make" \
         "$STAGE/var/mobile/tools/bin" \
         "$STAGE/DEBIAN"

cp "$BIN_SRC" "$STAGE/var/mobile/tools/make/make"
chmod 755 "$STAGE/var/mobile/tools/make/make"
ldid -S "$STAGE/var/mobile/tools/make/make"
ldid -e "$STAGE/var/mobile/tools/make/make" >/dev/null

ln -sf /var/mobile/tools/make/make "$STAGE/var/mobile/tools/bin/make"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: make4
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: GNU make 4.4.1 for iOS 10.3.3 armv7
 On-device rebuilds of small projects.  NLS off; eaccess/memrchr gnulib
 probes forced off (device lacks both -- gnulib supplies replacements);
 libgnu.a archived with darwin-ar (ld64 ignores GNU archives).  See
 make/build.sh for the full override list.
Section: devel
Priority: optional
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN="/var/mobile/tools/make/make"
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ -L "/var/mobile/tools/bin/make" ] && rm -f "/var/mobile/tools/bin/make" || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -8
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
