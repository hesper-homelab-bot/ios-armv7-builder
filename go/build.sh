#!/bin/bash
# Build the Go 1.27.2 darwin/arm revived port for armv7 iOS 10.x.
#
# Two artifacts:
#   * a host (linux/amd64) GOROOT that can cross-compile darwin/arm —
#     this is what tailcat and every other Go program in this repo is
#     built with (~/scratch/go-port is one such tree);
#   * an on-device toolchain tgz (bin/go + pkg/tool/darwin_arm/* + src +
#     pkg/include) that runs `go build` on the iPad itself.
#
# Everything that differs from upstream go1.27.2 lives in patches/
# (see patches/README.md for the why of every hunk).  The runtime fixes
# are load-bearing: without them every libc call trashes the trampoline
# return address (pc=0xc), os.File.Seek fails with EINVAL, directory
# iteration corrupts, and multi-threaded programs hang on SIGURG.
#
# Usage:
#   ./go/build.sh                          # -> out/go-host-*, out/goroot-arm-*
#   GO_TAR=/path/to/go1.27.2.src.tar.gz ./go/build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
GO_VERSION="${GO_VERSION:-1.27.2}"
GO_TAR="${GO_TAR:-$HOME/go-sdk/go$GO_VERSION.src.tar.gz}"
BOOTSTRAP="${GOROOT_BOOTSTRAP:-$HOME/go-sdk/go1.27.2}"

[ -f "$GO_TAR" ] || {
    echo "downloading official go$GO_VERSION sources (aliyun mirror)"
    curl -sL --max-time 300 -o "$GO_TAR" \
        "https://mirrors.aliyun.com/golang/go$GO_VERSION.src.tar.gz"
}
[ -x "$BOOTSTRAP/bin/go" ] || {
    echo "bootstrap toolchain not found at $BOOTSTRAP/bin/go" >&2
    exit 1
}

# /tmp on this host is a small tmpfs with per-user quota — Go builds
# (make.bash $WORK, link output) exceed it with "disk quota exceeded".
# Work on the root filesystem instead.
export TMPDIR="${TMPDIR:-$root/tmp}"
mkdir -p "$TMPDIR"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- unpack official sources and apply the port patches -------------------
mkdir -p "$work/goroot"
tar xzf "$GO_TAR" -C "$work/goroot" --strip-components=1
cd "$work/goroot"
for p in "$here"/patches/[0-9]*.patch; do
    echo "==> applying $(basename "$p")"
    patch -p1 --silent < "$p"
done

# --- host toolchain (linux/amd64, cross-compiles darwin/arm) --------------
cd "$work/goroot/src"
export GOROOT_BOOTSTRAP="$BOOTSTRAP"
unset GOOS GOARCH GOARM CGO_ENABLED 2>/dev/null || true
./make.bash 2>&1 | tail -3
export GOROOT="$work/goroot"

# --- sanity: the fresh host toolchain cross-builds a darwin/arm binary ----
cat > "$work/hello.go" <<'EOF'
package main
import "fmt"
func main() { fmt.Println("ok") }
EOF
GOOS=darwin GOARCH=arm GOARM=7 CGO_ENABLED=0 \
    "$work/goroot/bin/go" build -o "$work/hello" "$work/hello.go"
file "$work/hello" | grep -q "Mach-O armv7 executable" || {
    echo "sanity build did not produce a Mach-O armv7 executable" >&2; exit 1
}

# --- host toolchain artifact (before bin/go is replaced below) ------------
mkdir -p "$OUT"
tar czf "$OUT/go-host-$GO_VERSION-linux-amd64.tgz" -C "$work/goroot" \
    bin pkg/tool/linux_amd64 src pkg/include api VERSION

# --- on-device toolchain: cross-build the five commands (darwin/arm) -----
# Build to a temp name first: overwriting bin/go (the linux/amd64 host go)
# before the other four are built would leave the loop with no working
# compiler.
GOOS=darwin GOARCH=arm GOARM=7 CGO_ENABLED=0 "$work/goroot/bin/go" \
    build -ldflags "-s -w" -o "$work/goroot/bin/go.darwinarm" ./cmd/go \
    || { echo "cross-build of cmd/go failed" >&2; exit 1; }
file "$work/goroot/bin/go.darwinarm" | grep -q "Mach-O armv7 executable" || {
    echo "cmd/go output is not a Mach-O armv7 executable" >&2; exit 1
}
for t in compile link asm vet; do
    GOOS=darwin GOARCH=arm GOARM=7 CGO_ENABLED=0 "$work/goroot/bin/go" \
        build -ldflags "-s -w" -o "$work/goroot/pkg/tool/darwin_arm/$t" ./cmd/$t \
        || { echo "cross-build of cmd/$t failed" >&2; exit 1; }
    file "$work/goroot/pkg/tool/darwin_arm/$t" | grep -q "Mach-O armv7 executable" || {
        echo "cmd/$t output is not a Mach-O armv7 executable" >&2
        file "$work/goroot/pkg/tool/darwin_arm/$t" >&2
        exit 1
    }
done
mv "$work/goroot/bin/go.darwinarm" "$work/goroot/bin/go"

# The on-device tgz mirrors the layout /var/mobile/tools/goroot expects.
tar czf "$OUT/goroot-arm-$GO_VERSION.tgz" -C "$work/goroot" \
    bin/go pkg/tool/darwin_arm src pkg/include

echo "==> $OUT/goroot-arm-$GO_VERSION.tgz   (on-device toolchain)"
echo "==> $OUT/go-host-$GO_VERSION-linux-amd64.tgz (host cross toolchain)"
echo "    sanity build: $(file "$work/hello" | sed 's/.*: //')"
