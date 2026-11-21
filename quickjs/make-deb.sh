#!/bin/bash
# Package the QuickJS interpreter into a .deb for the APT repo.
#
# Installs /var/mobile/tools/bin/qjs (the interpreter).  qjsc (the bytecode
# compiler) stays a build-host tool here -- on-device JS deployment is a
# scripts-with-sources story, and shipping the host-crossed qjsc would be a
# second binary nobody executes on the device.
#
# Usage: ./quickjs/make-deb.sh        # after ./quickjs/build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
QJS_VERSION="${QJS_VERSION:-2026-06-04}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"

BIN="$root/tmp/src/quickjs-$QJS_VERSION/qjs"
[ -x "$BIN" ] || { echo "missing $BIN (run build.sh first)" >&2; exit 1; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools/bin" "$w/usr/share/doc/quickjs4"

cat > "$w/DEBIAN/control" <<CTRL
Package: quickjs4
Name: QuickJS JavaScript engine
Version: $QJS_VERSION-$DEBREV
Section: Development
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://bellard.org/quickjs/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: QuickJS $QJS_VERSION JavaScript engine for armv7 iOS 10+
 Fabrice Bellard's QuickJS (ES2023), cross-compiled for armv7 iOS 10.x.
 Installs /var/mobile/tools/bin/qjs.
 .
 Originally the comparison engine for the node.js port (docs/quickjs.md);
 productized 2026-11-21 with pinned sources, clean-tree rebuilds and the
 standard check-undefined gate.  test262 baseline: 58 known failures
 (host-run, recorded in the upstream tree and docs/quickjs.md).
CTRL

cat > "$w/usr/share/doc/quickjs4/changelog" <<CH
quickjs4 ($QJS_VERSION-$DEBREV) stable; urgency=medium

  * QuickJS $QJS_VERSION cross-built for armv7 iOS 10 on a Linux host.
  * Productized from the node-port comparison engine (phase 1).

 -- $MAINTAINER  $(date -R)
CH

# host ldid produces signatures the device rejects for *some* binaries
# (Killed: 9 with no crash report); sign on the device exactly like the
# other packaging scripts do -- copy over, sign there, fetch back.
stage="$OUT/.quickjs4-$QJS_VERSION-signed"
cp "$BIN" "$stage"
if command -v ldid >/dev/null 2>&1; then
    ldid -S "$stage"
else
    echo "host ldid missing -- install ldid or wire the device-sign path" >&2
    exit 1
fi

install -m 0755 "$stage" "$w/var/mobile/tools/bin/qjs"

deb="$OUT/quickjs4_${QJS_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
echo "==> $deb"
dpkg-deb -f "$deb" Package Version Architecture
sha256sum "$deb"
