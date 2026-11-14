#!/bin/bash
# make-deb.sh -- build p7zip16 deb for armv7 iOS 10.3.3
#
# Payload layout (DEVICE.md §3 conventions):
#   /var/mobile/tools/p7zip/7za   the real binary (root:wheel, host-signed)
#   /var/mobile/tools/bin/7za     symlink -> the real binary (login shells)
#   /var/mobile/tools/bin/7z      symlink -> the real binary
# The 2007-era p7zip 4.57 package keeps its dpkg-owned /usr/bin/7z and
# /usr/bin/7za untouched; a non-login shell (PATH=/usr/bin:/bin) still finds
# the old one, an interactive shell finds ours first via tools/bin.
#
# Package naming: the old jailbreak package is literally `p7zip 4.57-3p`, so
# reusing the name `p7zip` for ours would upgrade/collide with it in dpkg's
# eyes.  Distinct name `p7zip17` + real version 17.05-1 keeps the two
# installable side by side; ours lives only under /var/mobile/tools.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
UPSTREAM="17.05"                          # build.sh 的产物命名（7za-<UPSTREAM>-armv7）
VERSION="$UPSTREAM-1"                     # deb 版本
BIN_SRC="$REPO_OUT/7za-$UPSTREAM-armv7"   # build.sh 产物（未签名）
DEB="$REPO_OUT/p7zip17_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/p7zip17-stage"

[ -f "$BIN_SRC" ] || { echo "missing $BIN_SRC -- run build.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE/var/mobile/tools/p7zip" \
         "$STAGE/var/mobile/tools/bin" \
         "$STAGE/DEBIAN"

# 本体：签名 + 断言（§7/§10：签名必须验证，不许 || true）
cp "$BIN_SRC" "$STAGE/var/mobile/tools/p7zip/7za"
chmod 755 "$STAGE/var/mobile/tools/p7zip/7za"
ldid -S "$STAGE/var/mobile/tools/p7zip/7za"
ldid -e "$STAGE/var/mobile/tools/p7zip/7za" >/dev/null

# 两个入口（符号链接随包安装；prerm 负责清掉）
ln -sf /var/mobile/tools/p7zip/7za "$STAGE/var/mobile/tools/bin/7za"
ln -sf /var/mobile/tools/p7zip/7za "$STAGE/var/mobile/tools/bin/7z"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: p7zip17
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: p7zip 17.05 (7z/7za) for iOS 10.3.3 armv7
 Standalone 7za, all codecs built in: 7z (LZMA/LZMA2), xz, AES-256,
 gzip, bzip2, zip, tar.  Supersedes the 2007-era p7zip 4.57 in interactive
 PATHs via /var/mobile/tools/bin symlinks; the old package's dpkg-owned
 /usr/bin/7z and /usr/bin/7za are left untouched.
Section: utils
Priority: optional
EOF

# postinst: 断言装机后的签名仍在（移动/解包不改内容，纯属门禁）
cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN="/var/mobile/tools/p7zip/7za"
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

# prerm: 摘掉本包的入口符号链接（node4 同款守卫式写法）
cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
for t in 7za 7z; do
    [ -L "/var/mobile/tools/bin/$t" ] && rm -f "/var/mobile/tools/bin/$t" || true
done
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

# 打包：-Zgzip 铁律（toolchain.md §14.7：设备 dpkg 1.18.10 不认 zstd），
# --root-owner-group 与 lsof/make-deb.sh 同款。
dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -8
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
