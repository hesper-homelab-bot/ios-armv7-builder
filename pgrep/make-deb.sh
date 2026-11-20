#!/bin/bash
# Package pgrep+pkill as pgrep4_<ver>-1_iphoneos-arm.deb.
# One binary, two names (argv[0] dispatch); installs to /usr/bin.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
VER="${PGREP_VERSION:-1.1}"

for b in "$OUT/pgrep-armv7" "$OUT/pkill-armv7"; do
    [ -f "$b" ] || { echo "missing $b (run pgrep/build.sh)" >&2; exit 1; }
done

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/bin" "$w/usr/share/doc/pgrep4"

cat > "$w/DEBIAN/control" <<CTRL
Package: pgrep4
Name: pgrep/pkill $VER
Version: $VER-1
Section: Utils
Priority: optional
Architecture: iphoneos-arm
Maintainer: Hesper <hesperup@users.noreply.github.com>
Homepage: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: pgrep/pkill for armv7 iOS 10+ (sysctl, no /proc)
 OpenBSD-pkill-lineage process finder/killer adapted to Darwin: the
 process table comes from sysctl(KERN_PROC_ALL) -- iOS has no /proc.
 -f full-cmdline matching needs root (KERN_PROCARGS2 is root-only on
 iOS 10; non-root silently matches p_comm).  One binary, installed as
 both pgrep and pkill (argv[0] dispatch).
CTRL

cat > "$w/DEBIAN/postinst" <<POST
#!/bin/sh
set -e
if command -v ldid >/dev/null 2>&1; then
    ldid -S /usr/bin/pgrep 2>/dev/null || true
    ldid -S /usr/bin/pkill 2>/dev/null || true
fi
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"

install -m 755 "$OUT/pgrep-armv7" "$w/usr/bin/pgrep"
install -m 755 "$OUT/pkill-armv7" "$w/usr/bin/pkill"
cat > "$w/usr/share/doc/pgrep4/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: pkill
Source: adapted from OpenBSD usr.bin/pkill (BSD licence)

Files: *
Copyright: 2002 The NetBSD Foundation, Inc. (original pkill)
Copyright: 2026 Hesper <hesperup@users.noreply.github.com> (Darwin adaptation)
License: BSD-3-Clause
COPYRIGHT

dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/pgrep4_${VER}-1_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT
echo "==> $OUT/pgrep4_${VER}-1_iphoneos-arm.deb"
sha256sum "$OUT/pgrep4_${VER}-1_iphoneos-arm.deb"
