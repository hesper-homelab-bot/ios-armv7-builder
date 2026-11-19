#!/bin/bash
# Build tailscale v1.104.7 (CLI + daemon) for armv7 iOS 10.x with the
# Go 1.27.2 darwin/arm revived toolchain.
#
# The first tailscale ever to build for GOOS=darwin GOARCH=arm -- possible
# because of the ported GOROOT (~/scratch/go-port/go, docs/go.md) and the
# dependency adaptation set inherited from the tailcat 0.7.0 port
# (docs/tailcat-porting.md): x/sys v0.48 darwin/arm (+RTF_GLOBAL/RTF_DEAD/
# RTF_LLDATA for 32-bit, see docs/tailscale.md wall #1), x/net v0.60,
# u-root v0.16 -- all as local trees behind `replace`.
#
# Non-negotiable environment for this build:
#   * GOTOOLCHAIN=local -- the patched go.mod says `go 1.27.2`; with the
#     default `auto` go would fetch an UPSTREAM 1.27.x toolchain, which has
#     no darwin/arm target at all.
#   * TMPDIR off /tmp -- the host tmpfs has a per-user quota that the
#     tailscaled compile blows through ("disk quota exceeded"; wall #2,
#     second recurrence of the go/build.sh lesson).
#   * GOPROXY=goproxy.cn -- proxy.golang.org hangs for minutes here.
#   * -s -w -- the darwin/arm linker's __DWARF vmsize bug (see go.md).
#
# Usage:
#   ./tailscale/build.sh                  # -> ../out/tailscale{,d}-<ver>-armv7
#   TS_SRC=/path/to/tailscale ./tailscale/build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
GOPORT="${GOPORT:-$HOME/scratch/go-port/go/bin/go}"
SRC="${TS_SRC:-$HOME/scratch/tailscale/src}"

[ -x "$GOPORT" ] || { echo "go-port toolchain not found at $GOPORT" >&2; exit 1; }
[ -f "$SRC/go.mod" ] || { echo "tailscale source not found at $SRC" >&2; exit 1; }

VER="${TS_VERSION:-$(tr -d '[:space:]' < "$SRC/VERSION.txt")}"
LDF="-s -w -X tailscale.com/version.longStamp=v$VER -X tailscale.com/version.shortStamp=$VER"

mkdir -p "$OUT"
export GOTOOLCHAIN=local
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export TMPDIR="${TMPDIR:-$HOME/ios-armv7-builder/tmp}"
mkdir -p "$TMPDIR"

cd "$SRC"
for cmd in tailscale tailscaled; do
    GOOS=darwin GOARCH=arm GOARM=7 CGO_ENABLED=0 \
        "$GOPORT" build -tags netgo -ldflags "$LDF" \
        -o "$OUT/$cmd-$VER-armv7" "./cmd/$cmd"
    file "$OUT/$cmd-$VER-armv7" | grep -q "Mach-O armv7 executable" || {
        echo "$cmd: output is not a Mach-O armv7 executable:" >&2
        file "$OUT/$cmd-$VER-armv7" >&2
        exit 1
    }
    echo "==> $OUT/$cmd-$VER-armv7"
done
echo "    deploy: scp both to the device, then (as root) chmod 755 + chown mobile:mobile + ldid -S"
echo "    run:    tailscaled --tun=userspace-networking   (iOS 10 has no /dev/tun)"
