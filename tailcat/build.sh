#!/bin/bash
# Build tailcat (Go 1.27.2 darwin/arm revived port) for armv7 iOS 10.x.
#
# tailcat is the first real Go program to run on this target, and it is only
# possible because of the runtime fixes recorded in ../docs/tailcat-porting.md
# (commit ee291af1 in ~/scratch/go-port/go): without them every libc call
# trashed the trampoline's return address and died at pc=0xc.
#
# Toolchain notes that must stay true:
#   * ~/scratch/go-port/go is the ported GOROOT; `go install cmd/link` has
#     been run there after any cmd/link source change (go build does NOT
#     rebuild GOROOT tools by itself).
#   * GOPROXY defaults to goproxy.cn because proxy.golang.org hangs for
#     minutes in this network (a 20-minute "stuck build" was exactly this).
#   * -s -w is required: without it the linker emits a __DWARF segment with
#     filesize > vmsize and dyld refuses the image (known linker bug, see
#     docs/tailcat-porting.md).
#   * GODEBUG=asyncpreemptoff=1 is NOT needed anymore: after ee291af1 the
#     async preemption signal is handled fine in libc contexts (verified:
#     30 s of `serve` without it, daemon alive).  Keep it in mind only as a
#     variable to eliminate if a new weird crash shows up.
#
# Usage:
#   ./tailcat/build.sh                    # -> ../out/tailcat-<ver>-armv7
#   TCT_SRC=/path/to/tailcat/src ./tailcat/build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
GOPORT="${GOPORT:-$HOME/scratch/go-port/go/bin/go}"
SRC="${TCT_SRC:-$HOME/scratch/tailcat/src}"

[ -x "$GOPORT" ] || { echo "go-port toolchain not found at $GOPORT" >&2; exit 1; }
[ -f "$SRC/go.mod" ] || { echo "tailcat source not found at $SRC" >&2; exit 1; }

# Version matches the upstream release the source line sits on (v0.7.0);
# override with TCT_VERSION when building a different checkout.
VER="${TCT_VERSION:-0.7.0}"

mkdir -p "$OUT"

# proxy.golang.org is unreachable-slow here; goproxy.cn answers in <1 s.
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

cd "$SRC"
GOOS=darwin GOARCH=arm GOARM=7 CGO_ENABLED=0 \
    "$GOPORT" build -tags netgo -ldflags "-s -w" \
    -o "$OUT/tailcat-$VER-armv7" ./cmd/tailcat

# The output must be a Mach-O executable; building the repo root instead of
# ./cmd/tailcat would hand back an ar archive for the library, and this check
# keeps that mistake loud instead of shipping it.
file "$OUT/tailcat-$VER-armv7" | grep -q "Mach-O armv7 executable" || {
    echo "output is not a Mach-O armv7 executable:" >&2
    file "$OUT/tailcat-$VER-armv7" >&2
    exit 1
}

echo "==> $OUT/tailcat-$VER-armv7"
echo "    deploy: scp it to the device, then (as root) chmod 755 + chown mobile:mobile + ldid -S"
