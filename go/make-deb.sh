#!/bin/bash
# Package the on-device Go toolchain into a .deb for the APT repo.
#
# Installs the revived darwin/arm Go 1.27.2 toolchain so `go build` runs on
# the iPad itself:
#
#   /var/mobile/tools/goroot/bin/go
#   /var/mobile/tools/goroot/pkg/tool/darwin_arm/{compile,link,asm,vet}
#   /var/mobile/tools/goroot/src            (full std sources)
#   /var/mobile/tools/goroot/pkg/include    (asm headers)
#
# No launchd daemon, no conffiles.  The five armv7 Mach-O binaries are
# host-side ldid -S signed by this script; the device-side runtime has also
# been observed to need a re-sign on install for some hosts, so postinst
# re-runs ldid -S (same pattern as tailcat4).
#
# Prerequisite: ./build.sh has produced ../out/goroot-arm-<ver>.tgz.
#
# Usage:
#   ./go/build.sh && ./go/make-deb.sh
#   DEBREV=2 ./go/make-deb.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
PKG="go4"
GO_VERSION="${GO_VERSION:-1.27.2}"

TGZ="$OUT/goroot-arm-$GO_VERSION.tgz"
[ -f "$TGZ" ] || { echo "no $TGZ -- run ./go/build.sh first" >&2; exit 1; }

sign() {
    local dst="$1"
    command -v ldid >/dev/null 2>&1 || {
        echo "ldid is not on PATH -- refusing to package unsigned binaries" >&2
        exit 1
    }
    ldid -S "$dst" || { echo "ldid -S failed for $dst" >&2; exit 1; }
    ldid -e "$dst" >/dev/null 2>&1 || {
        echo "$dst carries no signature after ldid -S" >&2
        exit 1
    }
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools/goroot" "$w/usr/share/doc/$PKG"

tar xzf "$TGZ" -C "$w/var/mobile/tools/goroot"

# sign the five armv7 executables
for b in bin/go pkg/tool/darwin_arm/compile pkg/tool/darwin_arm/link \
         pkg/tool/darwin_arm/asm pkg/tool/darwin_arm/vet; do
    sign "$w/var/mobile/tools/goroot/$b"
done

# sources may not need exec bits; keep binaries tight
chmod 755 "$w/var/mobile/tools/goroot/bin/go" "$w"/var/mobile/tools/goroot/pkg/tool/darwin_arm/*

cat > "$w/DEBIAN/control" <<CTRL
Package: $PKG
Name: Go $GO_VERSION darwin/arm
Version: $GO_VERSION-$DEBREV
Section: Development
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://go.dev/
Description: Go $GO_VERSION toolchain for armv7 iOS, revived port
 Go compiler and toolchain running on the device itself (armv7 iOS 10).
 The darwin/arm port was dropped upstream after Go 1.14; this revives it
 inside the Go 1.27.2 tree (internal-linking Mach-O writer, pure-Go
 runtime, per-thread g-slot table).  See the porting notes in the repo
 docs for the runtime and linker bugs that had to be fixed first.
 .
 Usage:
 .
   export GOROOT=/var/mobile/tools/goroot
   cd /var/mobile/gohello && go build -o hello .
 .
 First full build of a multi-package program takes minutes on an A6X.
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
CTRL

cat > "$w/DEBIAN/postinst" <<'POST'
#!/bin/sh
# Some hosts' ldid signatures are not accepted by the device kernel policy
# after unpacking (Killed: 9 before main); re-sign on the device.
if command -v ldid >/dev/null 2>&1; then
    for b in /var/mobile/tools/goroot/bin/go \
             /var/mobile/tools/goroot/pkg/tool/darwin_arm/compile \
             /var/mobile/tools/goroot/pkg/tool/darwin_arm/link \
             /var/mobile/tools/goroot/pkg/tool/darwin_arm/asm \
             /var/mobile/tools/goroot/pkg/tool/darwin_arm/vet; do
        ldid -S "$b" || true
    done
fi
POST
chmod 755 "$w/DEBIAN/postinst"

cat > "$w/usr/share/doc/$PKG/changelog" <<CH
$PKG ($GO_VERSION-$DEBREV) stable; urgency=medium

  * Go $GO_VERSION darwin/arm revived port, toolchain running on the device.
  * go version / go list / go build verified on iPad4 (iOS 10.3.3).
  * Per-thread g-slot table, async preemption disabled, internal-linking
    Mach-O writer with PLT stub symtab entries and iOS-10-safe __DWARF
    segment layout.
  * Sources are shipped so no separate std checkout is needed.

 -- $MAINTAINER  $(date -R)
CH

deb="$OUT/${PKG}_${GO_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb -Zgzip --root-owner-group -b "$w" "$deb"
echo "==> $deb"
echo "    installs /var/mobile/tools/goroot (go + compile/link/asm/vet + std sources)"
