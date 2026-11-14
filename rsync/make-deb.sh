#!/bin/bash
# make-deb.sh -- build rsync4 deb for armv7 iOS 10.3.3
#
# Payload layout (p7zip17 pattern):
#   /var/mobile/tools/rsync/rsync   the real binary (root:wheel, host-signed)
#   /var/mobile/tools/bin/rsync     symlink (login shells; non-login shells
#                                   keep PATH=/usr/bin:/bin)
# Over-ssh callers must pass --rsync-path=/var/mobile/tools/bin/rsync because
# the remote shell is non-login.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
UPSTREAM="3.3.0"                          # build.sh 产物命名（rsync-<UPSTREAM>-armv7）
VERSION="$UPSTREAM-1"                     # deb 版本
BIN_SRC="$REPO_OUT/rsync-$UPSTREAM-armv7" # build.sh 产物（未签名）
DEB="$REPO_OUT/rsync4_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/rsync4-stage"

[ -f "$BIN_SRC" ] || { echo "missing $BIN_SRC -- run build.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE/var/mobile/tools/rsync" \
         "$STAGE/var/mobile/tools/bin" \
         "$STAGE/DEBIAN"

# 本体：签名 + 断言（§7/§10：签名必须验证，不许 || true）
cp "$BIN_SRC" "$STAGE/var/mobile/tools/rsync/rsync"
chmod 755 "$STAGE/var/mobile/tools/rsync/rsync"
ldid -S "$STAGE/var/mobile/tools/rsync/rsync"
ldid -e "$STAGE/var/mobile/tools/rsync/rsync" >/dev/null

ln -sf /var/mobile/tools/rsync/rsync "$STAGE/var/mobile/tools/bin/rsync"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: rsync4
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: rsync 3.3.0 for iOS 10.3.3 armv7
 Fast incremental file transfer.  popt/zlib bundled in-tree; built without
 iconv/acl/xattr/xxhash/openssl extras (see rsync/build.sh for the probe
 overrides).  Over ssh use --rsync-path=/var/mobile/tools/bin/rsync.
Section: net
Priority: optional
EOF

# postinst: 断言装机后的签名仍在
cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN="/var/mobile/tools/rsync/rsync"
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

# prerm: 摘掉入口符号链接
cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ -L "/var/mobile/tools/bin/rsync" ] && rm -f "/var/mobile/tools/bin/rsync" || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

# 打包：-Zgzip 铁律（toolchain.md §14.7）+ --root-owner-group
dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -8
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
