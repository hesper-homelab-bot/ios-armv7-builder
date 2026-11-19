#!/bin/bash
# Package the armv7 tailcat build into a .deb for the APT repo.
#
# tailcat is a user-run networking tool, not a daemon, so this package is
# deliberately the simplest one in the tree:
#
#   * one self-contained binary, /var/mobile/tools/tailcat (no prefix and no
#     symlink games -- the system has no tailcat of its own to shadow);
#   * no LaunchDaemon, no wrapper, no conffiles: tailcat serve is started by
#     the person using it, and its state lives in the user's config dir;
#   * host-side ldid -S only, exactly like openssh4/dropbear4 (the device
#     kills an unsigned Mach-O with SIGKILL before main()).
#
# Prerequisite: ./build.sh has produced ../out/tailcat-<ver>-armv7.
#
# Usage:
#   ./tailcat/build.sh && ./tailcat/make-deb.sh
#   DEBREV=2 ./tailcat/make-deb.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
PKG="tailcat4"

# The binary whose version the build stamped into its name.  There is exactly
# one tailcat-* in out/, so refusing to guess is cheap.
cands=("$OUT"/tailcat-*-armv7)
[ -f "${cands[0]}" ] || { echo "no tailcat-*-armv7 in $OUT -- run ./tailcat/build.sh first" >&2; exit 1; }
[ "${#cands[@]}" -eq 1 ] || {
    echo "multiple tailcat binaries in $OUT, remove the stale ones:" >&2
    printf '  %s\n' "${cands[@]}" >&2
    exit 1
}
BIN="${cands[0]}"
VER="${TCT_VERSION:-0.7.0}"

# Same contract as openssh/make-deb.sh sign(): failures must be loud, and the
# signature is asserted with ldid -e so a silently-unsigned binary can never
# reach the package (that folklore "host ldid is unreliable" came from a
# swallowed failure, not from ldid).
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst" || { echo "cp failed: $src -> $dst" >&2; exit 1; }
    command -v ldid >/dev/null 2>&1 || {
        echo "ldid is not on PATH -- refusing to package an unsigned binary" >&2
        exit 1
    }
    ldid -S "$dst" || { echo "ldid -S failed for $dst" >&2; exit 1; }
    ldid -e "$dst" >/dev/null 2>&1 || {
        echo "$dst carries no signature after ldid -S" >&2
        exit 1
    }
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools" "$w/usr/share/doc/$PKG"

cat > "$w/DEBIAN/control" <<CTRL
Package: $PKG
Name: tailcat $VER
Version: $VER-$DEBREV
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://github.com/tailscale/tailcat
Description: tailcat for armv7 iOS, Go 1.27.2 darwin/arm revived port
 Securely pipe or serve network connections over Tailscale's data plane
 (WireGuard, NAT traversal) without Tailscale's control plane.  Built with
 the revived Go 1.27.2 darwin/arm toolchain; see the porting notes in the
 repo docs for the runtime bugs that had to be fixed first.
 .
 No launchd daemon: run it yourself, e.g.
 .
   /var/mobile/tools/tailcat serve
 .
 or pipe through it:
 .
   /var/mobile/tools/tailcat <address>
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
CTRL

cat > "$w/DEBIAN/postinst" <<'POST'
#!/bin/sh
# The host-side ldid signature is NOT accepted by the iOS 10 kernel policy
# on this target: an installed-but-host-signed tailcat dies with "Killed: 9"
# before main().  Re-signing with the on-device ldid fixes it (verified
# 2026-11-18), so do that automatically on every install/upgrade.
if [ -x /usr/bin/ldid ] || command -v ldid >/dev/null 2>&1; then
    ldid -S /var/mobile/tools/tailcat
fi
POST
chmod 755 "$w/DEBIAN/postinst"

cat > "$w/usr/share/doc/$PKG/changelog" <<CH
$PKG ($VER-$DEBREV) stable; urgency=medium

  * tailcat $VER, Go 1.27.2 darwin/arm port (~/scratch/go-port).
  * First Go program to run fully on armv7 iOS 10: required the
    syscallN_trampoline reservation-scale and small-arity fixes
    (go-port commit ee291af1) plus PLT stub symtab entries
    (commit e1f54449) in the linker.
  * Single binary, no daemon, no conffiles; GODEBUG tweaks not needed.

 -- $MAINTAINER  $(date -R)
CH

sign "$BIN" "$w/var/mobile/tools/tailcat"
chmod 755 "$w/var/mobile/tools/tailcat"

deb="$OUT/${PKG}_${VER}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb -Zgzip --root-owner-group -b "$w" "$deb"
echo "==> $deb"
echo "    installs /var/mobile/tools/tailcat (single binary, no daemon)"
