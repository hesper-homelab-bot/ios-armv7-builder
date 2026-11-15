#!/bin/bash
# make-deb.sh -- build uuidgen deb for armv7 iOS 10.3.3
#
# Payload layout (class-dump4/p7zip17 pattern):
#   /var/mobile/tools/uuidgen/uuidgen  the real binary (signed, mobile-owned)
#   /var/mobile/tools/bin/uuidgen      symlink (login shells)
# Headers: real iPhoneOS10.3.sdk (xybp888/iOS-SDKs); first port under the
# SDK sysroot mode default (AGENTS.md rule 5).  No Depends: everything
# binds to the device's libSystem at runtime (uuid_* left undefined at
# link time on purpose).
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
UPSTREAM="$(ls "$REPO_OUT"/uuidgen-*-armv7 2>/dev/null | sed "s|.*/uuidgen-\(.*\)-armv7|\1|" | head -1)"
VERSION="$UPSTREAM-1"
BIN_SRC="$REPO_OUT/uuidgen-$UPSTREAM-armv7" # build.sh 产物（未签名）
DEB="$REPO_OUT/uuidgen_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/uuidgen-stage"

[ -f "$BIN_SRC" ] || { echo "missing $BIN_SRC -- run build.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE/var/mobile/tools/uuidgen" \
         "$STAGE/var/mobile/tools/bin" \
         "$STAGE/DEBIAN"

cp "$BIN_SRC" "$STAGE/var/mobile/tools/uuidgen/uuidgen"
chmod 755 "$STAGE/var/mobile/tools/uuidgen/uuidgen"
ldid -S "$STAGE/var/mobile/tools/uuidgen/uuidgen"
ldid -e "$STAGE/var/mobile/tools/uuidgen/uuidgen" >/dev/null

ln -sf /var/mobile/tools/uuidgen/uuidgen "$STAGE/var/mobile/tools/bin/uuidgen"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: uuidgen
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: uuidgen (e2fsprogs 1.47.2) for iOS 10.3.3 armv7
 Generates RFC 4122 UUIDs: default and -r random (v4), -t time-based (v1).
 Replacement for the BigBoss 'uuid' CLI, whose dyld loading is broken on
 iOS 10.3.3 (libgcc_s re-export failure, Abort trap 6).  Built against the
 real iPhoneOS10.3.sdk headers; uuid_* calls bind to the device's libSystem
 at runtime.
Section: sysutils
Priority: optional
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN="/var/mobile/tools/uuidgen/uuidgen"
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ -L "/var/mobile/tools/bin/uuidgen" ] && rm -f "/var/mobile/tools/bin/uuidgen" || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -8
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
