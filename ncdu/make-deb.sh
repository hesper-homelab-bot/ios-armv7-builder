#!/bin/bash
# Package ncdu as ncdu4_<ver>_iphoneos-arm.deb.
# 运行时依赖设备自带 /usr/lib/libncursesw.5.dylib(1.20 不带 ncurses)。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
VER="${NCDU_VERSION:-1.20}"
BIN="$OUT/ncdu4-armv7"
[ -f "$BIN" ] || { echo "missing $BIN (run ncdu/build.sh)" >&2; exit 1; }
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/bin" "$w/var/mobile/tools/ncdu" "$w/usr/share/doc/ncdu4"
cat > "$w/DEBIAN/control" <<CTRL
Package: ncdu4
Name: ncdu
Version: $VER-1
Section: Utilities
Priority: optional
Architecture: iphoneos-arm
Maintainer: Hesper <hesperup@users.noreply.github.com>
Homepage: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: ncdu 1.20 ncurses disk usage analyzer for armv7 iOS 10+
 TUI disk usage explorer (du with a curses interface).  Links against the
 device's own libncursesw.5.dylib.  Also supports -o/-f JSON export/import
 for non-interactive use.
CTRL
cat > "$w/DEBIAN/postinst" <<POST
#!/bin/sh
set -e
if command -v ldid >/dev/null 2>&1; then
    ldid -S /var/mobile/tools/ncdu/ncdu 2>/dev/null || true
fi
chown mobile:mobile /var/mobile/tools/ncdu/ncdu 2>/dev/null || true
chmod 0755 /var/mobile/tools/ncdu/ncdu 2>/dev/null || true
ln -sf /var/mobile/tools/ncdu/ncdu /usr/bin/ncdu
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"
cat > "$w/DEBIAN/prerm" <<PRERM
#!/bin/sh
set -e
rm -f /usr/bin/ncdu
exit 0
PRERM
chmod 0755 "$w/DEBIAN/prerm"
install -m 0755 "$BIN" "$w/var/mobile/tools/ncdu/ncdu"
cat > "$w/usr/share/doc/ncdu4/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ncdu
Source: https://dev.yorhel.nl/download/ncdu-1.20.tar.gz (MIT)

Files: *
Copyright: 2006-2023 Yorhel
License: MIT
COPYRIGHT
dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/ncdu4_${VER}-1_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT
echo "==> $OUT/ncdu4_${VER}-1_iphoneos-arm.deb"
sha256sum "$OUT/ncdu4_${VER}-1_iphoneos-arm.deb"
