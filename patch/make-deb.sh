#!/bin/bash
# Package patch as patch4_<ver>_iphoneos-arm.deb.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
VER="${PATCH_VERSION:-2.7.1}"
BIN="$OUT/patch4-armv7"
[ -f "$BIN" ] || { echo "missing $BIN (run patch/build.sh)" >&2; exit 1; }
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/bin" "$w/var/mobile/tools/patch" "$w/usr/share/doc/patch4"
cat > "$w/DEBIAN/control" <<CTRL
Package: patch4
Name: GNU patch
Version: $VER-1
Section: Utilities
Priority: optional
Architecture: iphoneos-arm
Maintainer: Hesper <hesperup@users.noreply.github.com>
Homepage: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: GNU patch 2.7.1 for armv7 iOS 10+ (apply unified diffs on device)
 The standard patch(1): applies unified/context diffs, with gnulib probes
 suppressed for iOS 10 (futimens/utimensat/nanotime fall back to utimes).
CTRL
cat > "$w/DEBIAN/postinst" <<POST
#!/bin/sh
set -e
if command -v ldid >/dev/null 2>&1; then
    ldid -S /var/mobile/tools/patch/patch 2>/dev/null || true
fi
chown mobile:mobile /var/mobile/tools/patch/patch 2>/dev/null || true
chmod 0755 /var/mobile/tools/patch/patch 2>/dev/null || true
ln -sf /var/mobile/tools/patch/patch /usr/bin/patch
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"
cat > "$w/DEBIAN/prerm" <<PRERM
#!/bin/sh
set -e
rm -f /usr/bin/patch
exit 0
PRERM
chmod 0755 "$w/DEBIAN/prerm"
install -m 0755 "$BIN" "$w/var/mobile/tools/patch/patch"
cat > "$w/usr/share/doc/patch4/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: patch
Source: https://ftp.gnu.org/gnu/patch/patch-2.7.1.tar.gz (GPL-3+)

Files: *
Copyright: 1984-2012 Larry Wall, Andreas Gruenbacher et al.
License: GPL-3+
COPYRIGHT
dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/patch4_${VER}-1_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT
echo "==> $OUT/patch4_${VER}-1_iphoneos-arm.deb"
sha256sum "$OUT/patch4_${VER}-1_iphoneos-arm.deb"
