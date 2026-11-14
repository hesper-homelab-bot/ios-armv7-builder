#!/bin/bash
# make-deb.sh -- build class-dump4 deb for armv7 iOS 10.3.3
#
# Payload layout (p7zip17 pattern):
#   /var/mobile/tools/class-dump/class-dump  the real binary (root:wheel, signed)
#   /var/mobile/tools/bin/class-dump         symlink (login shells)
# Headers: real iPhoneOS10.3.sdk (xybp888/iOS-SDKs); links Foundation/
# CoreFoundation via the SDK's official tbd stubs; ObjC class refs bind via
# the runtime (see build.sh ALLOWED_UNDEFINED note).
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
UPSTREAM="$(ls "$REPO_OUT"/class-dump-*-armv7 2>/dev/null | sed "s|.*/class-dump-\(.*\)-armv7|\1|" | head -1)"
VERSION="$UPSTREAM-1"
BIN_SRC="$REPO_OUT/class-dump-$UPSTREAM-armv7" # build.sh 产物（未签名）
DEB="$REPO_OUT/class-dump4_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/class-dump4-stage"

[ -f "$BIN_SRC" ] || { echo "missing $BIN_SRC -- run build.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE/var/mobile/tools/class-dump" \
         "$STAGE/var/mobile/tools/bin" \
         "$STAGE/DEBIAN"

cp "$BIN_SRC" "$STAGE/var/mobile/tools/class-dump/class-dump"
chmod 755 "$STAGE/var/mobile/tools/class-dump/class-dump"
ldid -S "$STAGE/var/mobile/tools/class-dump/class-dump"
ldid -e "$STAGE/var/mobile/tools/class-dump/class-dump" >/dev/null

ln -sf /var/mobile/tools/class-dump/class-dump "$STAGE/var/mobile/tools/bin/class-dump"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: class-dump4
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: class-dump (nygard fork 2c82b4f) for iOS 10.3.3 armv7
 Examines the Objective-C runtime segment of Mach-O files.  Built against
 the real iPhoneOS10.3.sdk headers (xybp888/iOS-SDKs); links Foundation/
 CoreFoundation via official tbd stubs.  MRC weak refs downgraded to
 unsafe_unretained (CLI lifecycle -- see class-dump/build.sh).
Section: sysutils
Priority: optional
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN="/var/mobile/tools/class-dump/class-dump"
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ -L "/var/mobile/tools/bin/class-dump" ] && rm -f "/var/mobile/tools/bin/class-dump" || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -8
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
