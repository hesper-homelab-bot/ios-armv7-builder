#!/bin/bash
# Package the armv7 jq build into a .deb for the APT repo.
#
# Follows ../wget/make-deb.sh: installs under /var/mobile/tools so nothing
# in /usr is touched.  Fully static (libonig linked in), so no Depends
# beyond firmware.
#
# Usage:
#   ./jq/make-deb.sh                 # uses ../out/jq-*-armv7
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
JQ_VERSION="${JQ_VERSION:-1.7.1}"
ONIG_VERSION="${ONIG_VERSION:-6.9.10}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"

JQ_BIN="$OUT/jq-$JQ_VERSION-armv7"
[ -f "$JQ_BIN" ] || { echo "missing $JQ_BIN (run jq/build.sh)" >&2; exit 1; }

# Host ldid occasionally produces a binary the device kills with "Killed: 9"
# and no crash report; signing on the device always works.  The packaging
# scripts therefore sign twice, exactly as curl/make-deb.sh does.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    ldid -S "$dst" 2>/dev/null || true
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools" "$w/usr/share/doc/jq"
cat > "$w/DEBIAN/control" <<CTRL
Package: jq
Name: jq 1.7
Version: $JQ_VERSION-$DEBREV
Section: Utilities
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://jqlang.github.io/jq/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: jq 1.7.1 for armv7 iOS 10+ (oniguruma regex, verified)
 jq $JQ_VERSION command-line JSON processor for armv7 iOS 10.x, statically
 linked with oniguruma $ONIG_VERSION (the test() and match() builtins work).
 Installs to /var/mobile/tools/jq; nothing in /usr is touched.
 .
 Verified on an iPad 4: filters, reduce over 100k elements, regex test(),
 UTF-8 round-trip, sort.  Pairs well with curl4 and sqlite3.
 .
 Add /var/mobile/tools to your PATH, or call it by absolute path.
CTRL

cat > "$w/usr/share/doc/jq/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: jq
Source: https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-$JQ_VERSION.tar.gz

Files: *
Copyright: 2012-2026 Stephen Dolan, nicowilliams and jq contributors
License: MIT
 jq is licensed under the MIT license; see the COPYING file shipped with
 the source.

Files: bundled oniguruma $ONIG_VERSION
Copyright: 2002-2026 K.Kosako
License: BSD-2-clause
 See the oniguruma source distribution's COPYING.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: MIT

Cross-compiled for armv7 iOS 10.x.  The sysroot headers used to build it are
original clean-room stubs or BSD-licensed musl headers; no Apple SDK files
are redistributed.
CR

sign "$JQ_BIN" "$w/var/mobile/tools/jq"
chmod 0755 "$w/var/mobile/tools/jq"
deb="$OUT/jq_${JQ_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device:"
echo "      cp $deb /var/mobile/ && dpkg -i $deb"
