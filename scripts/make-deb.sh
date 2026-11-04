#!/bin/bash
# Build a Cydia/BigBoss .deb from a built tmux binary.
#
# The binary must be ad-hoc signed (ldid).  If SIGNED_BIN is set it is used
# as-is; otherwise the unsigned artifact is uploaded to $DEVICE, signed with
# the device's own ldid, and fetched back.
#
# Usage:
#   TMUX_VERSION=3.8 DEVICE=ipad ./scripts/make-deb.sh
#   TMUX_VERSION=3.8 SIGNED_BIN=out/tmux-3.8-armv7.signed ./scripts/make-deb.sh
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
TMUX_VERSION="${TMUX_VERSION:-3.8}"
DEBREV="${DEBREV:-1}"
DEVICE="${DEVICE:-}"
SIGNED_BIN="${SIGNED_BIN:-}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
OUT="$here/out"

ART="$OUT/tmux-$TMUX_VERSION-armv7"
[ -f "$ART" ] || { echo "missing built binary: $ART (run build.sh first)" >&2; exit 1; }

if [ -z "$SIGNED_BIN" ]; then
    [ -n "$DEVICE" ] || { echo "set DEVICE (ssh host) or SIGNED_BIN" >&2; exit 1; }
    echo "==> signing on $DEVICE with its ldid"
    scp -o BatchMode=yes "$ART" "$DEVICE:/var/mobile/.tmux-sign.tmp" >/dev/null
    ssh -o BatchMode=yes "$DEVICE" \
        'chmod +x /var/mobile/.tmux-sign.tmp && ldid -S /var/mobile/.tmux-sign.tmp' \
        >/dev/null 2>&1
    SIGNED_BIN="$OUT/.tmux-$TMUX_VERSION-signed"
    scp -o BatchMode=yes "$DEVICE:/var/mobile/.tmux-sign.tmp" "$SIGNED_BIN" >/dev/null
    ssh -o BatchMode=yes "$DEVICE" 'rm -f /var/mobile/.tmux-sign.tmp' >/dev/null
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/DEBIAN" \
         "$work/usr/bin" \
         "$work/usr/share/man/man1" \
         "$work/usr/share/doc/tmux"

cat > "$work/DEBIAN/control" <<CTRL
Package: tmux
Name: tmux
Version: $TMUX_VERSION-$DEBREV
Section: Terminal Utilities
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Author: Nicholas Marriott <nicholas.marriott@gmail.com>
Homepage: https://github.com/tmux/tmux
Depiction: https://github.com/hesper-homelab-bot/ios-tmux-builder
Depends: firmware (>= 10.3)
Description: Terminal multiplexer - windows, panes, detachable sessions
 tmux is a terminal multiplexer: switch between several programs in one
 terminal, detach sessions (they keep running in the background) and
 reattach later, share sessions across SSH logins, and split windows into
 panes.
 .
 Cross-compiled from upstream source for armv7 iOS 10.x (no Xcode, no iOS
 SDK). Requires iOS 10.3 or later on an armv7 (32-bit) device.
CTRL

cat > "$work/usr/share/doc/tmux/copyright" <<'CR'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: tmux
Source: https://github.com/tmux/tmux

Files: *
Copyright: 2007-2024 Nicholas Marriott <nicholas.marriott@gmail.com>
           and tmux contributors
License: ISC
 Permission to use, copy, modify, and distribute this software for any
 purpose with or without fee is hereby granted, provided that the above
 copyright notice and this permission notice appear in all copies.
 .
 THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 WHATSOEVER RESULTING FROM LOSS OF MIND, USE, DATA OR PROFITS, WHETHER
 IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
 OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: ISC
 Packaging for the armv7 iOS port; same ISC terms as upstream.
CR

install -m 0755 "$SIGNED_BIN" "$work/usr/bin/tmux"
SRC="$(find "$here/tmp/src" -maxdepth 1 -type d -name "tmux-$TMUX_VERSION" | head -1)"
if [ -n "${SRC:-}" ] && [ -f "$SRC/tmux.1" ]; then
    gzip -9 -c "$SRC/tmux.1" > "$work/usr/share/man/man1/tmux.1.gz"
fi

deb="$OUT/tmux_${TMUX_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$work" "$deb" >/dev/null
echo "==> $deb"
dpkg-deb -f "$deb" Package Version Architecture
sha256sum "$deb"
