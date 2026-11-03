#!/bin/bash
# ============================================================================
#  ios-tmux-builder — build tmux for a jailbroken 32-bit iOS device (armv7),
#  on a Linux host, with no Xcode and no iOS SDK.
#
#  Result: a Mach-O armv7 executable (LC_VERSION_MIN_IPHONEOS 10.3) that links
#  against the device's own libSystem and libncursesw.
#
#  Usage:
#     ./build.sh                          # newest tmux release
#     TMUX_VERSION=3.5a ./build.sh        # a specific one
#     DEVICE=myipad ./build.sh            # ssh host to pull ncurses headers from
#
#  Required in the environment (or edit the defaults below):
#     LD64          path to cctools-port's x86_64-apple-darwin*-ld
#     LD64_LIBS     LD_LIBRARY_PATH needed by that ld64 (libdispatch, tapi)
# ============================================================================
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

# --------------------------------------------------------------- configuration
TMUX_VERSION="${TMUX_VERSION:-latest}"
LIBEVENT_VERSION="${LIBEVENT_VERSION:-2.1.12-stable}"
MUSL_VERSION="${MUSL_VERSION:-1.2.5}"
# musl.libc.org is unreachable from some networks; override with MUSL_URL
# (a mirror, or a URL to the same tarball).
MUSL_URL="${MUSL_URL:-https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz}"
TARGET_IOS="${TARGET_IOS:-10.3}"          # minimum iOS version
ARCH="${ARCH:-armv7}"
# musl names its 32-bit ARM port "arm"; armv6/armv7/armv7s all use it
MUSL_ARCH="${MUSL_ARCH:-arm}"
DEVICE="${DEVICE:-}"                      # ssh host; empty = ask for a dir

WORK="${WORK:-$here/tmp}"
OUT="${OUT:-$here/out}"
SYSROOT="$WORK/sysroot"
PREFIX="$WORK/install"
STUBDIR="$WORK/stubs"
DHDR="$WORK/device-headers"               # ncurses headers copied off the device

LD64="${LD64:-}"
LD64_LIBS="${LD64_LIBS:-}"

CLANG="${CLANG:-clang}"
LLVM_AR="${LLVM_AR:-}"
LLVM_NM="${LLVM_NM:-}"

# pick_tool VAR candidate... — set VAR to the first candidate that exists.
# Distros ship versioned names (llvm-ar-21, llvm-nm-21, ...), so hardcoding
# "llvm-ar" breaks the build with an unhelpful 127.
pick_tool() {
    local var="$1"; shift
    local cur c
    eval "cur=\${$var}"
    if [ -n "$cur" ]; then
        if command -v "$cur" >/dev/null 2>&1 || [ -x "$cur" ]; then
            return 0
        fi
    fi
    for c in "$@"; do
        if command -v "$c" >/dev/null 2>&1; then
            eval "$var=\$c"
            return 0
        fi
    done
    return 1
}

# fetch URL DEST — retries, because the release hosts occasionally drop TLS
fetch() {
    local url="$1" dest="$2" i
    [ -s "$dest" ] && return 0
    for i in 1 2 3 4 5; do
        if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 \
                -o "$dest.part" "$url"; then
            mv "$dest.part" "$dest"
            return 0
        fi
        warn "download failed (attempt $i): $url"
        rm -f "$dest.part"
        sleep 3
    done
    die "could not download $url"
}

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ preflight
preflight() {
    say "checking the host toolchain"
    pick_tool LLVM_AR llvm-ar llvm-ar-21 llvm-ar-20 llvm-ar-19 \
        /usr/lib/llvm-*/bin/llvm-ar || die "llvm-ar not found"
    pick_tool LLVM_NM llvm-nm llvm-nm-21 llvm-nm-20 llvm-nm-19 \
        /usr/lib/llvm-*/bin/llvm-nm || die "llvm-nm not found"
    for c in "$CLANG" "$LLVM_AR" curl tar make; do
        command -v "$c" >/dev/null || die "'$c' not found"
    done
    if [ -z "$LD64" ]; then
        for cand in /usr/local/osxcross/bin/*-ld /opt/osxcross/bin/*-ld \
                    "$HOME"/ios-tool/x-ld64/bin/*-ld; do
            [ -x "$cand" ] && LD64="$cand" && break
        done
    fi
    [ -n "$LD64" ] && [ -x "$LD64" ] || die "set LD64 to cctools-port's ld64"
    info="$("$CLANG" -print-targets 2>/dev/null | grep -c arm || true)"
    echo "    clang   : $($CLANG --version | head -1)"
    echo "    llvm-ar : $($LLVM_AR --version | head -1)"
    echo "    ld64    : $LD64"
    echo "    target  : $ARCH-apple-ios$TARGET_IOS"
}

# --------------------------------------------------------------------- sources
fetch_tmux_version() {
    if [ "$TMUX_VERSION" = latest ]; then
        say "looking up the newest tmux release"
        TMUX_VERSION="$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 \
            https://api.github.com/repos/tmux/tmux/releases/latest 2>/dev/null \
            | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
        [ -n "$TMUX_VERSION" ] || die "could not reach the GitHub API; set TMUX_VERSION"
    fi
    echo "    tmux $TMUX_VERSION"
}

fetch_sources() {
    mkdir -p "$WORK/src" && cd "$WORK/src"
    local tmux_tar="tmux-$TMUX_VERSION.tar.gz"
    [ -f "$tmux_tar" ] || curl -fL -o "$tmux_tar" \
        "https://github.com/tmux/tmux/releases/download/$TMUX_VERSION/tmux-$TMUX_VERSION.tar.gz"
    local le_tar="libevent-$LIBEVENT_VERSION.tar.gz"
    [ -f "$le_tar" ] || curl -fL -o "$le_tar" \
        "https://github.com/libevent/libevent/releases/download/release-$LIBEVENT_VERSION/libevent-$LIBEVENT_VERSION.tar.gz"
    local musl_tar="musl-$MUSL_VERSION.tar.gz"
    [ -f "$musl_tar" ] || curl -fL -o "$musl_tar" \
        "https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz"
    local f
    for f in "$tmux_tar" "$le_tar" "$musl_tar"; do
        local dir="${f%.tar.gz}"
        [ -d "$dir" ] || tar xzf "$f"
    done
    # tmux-3.5a / libevent-2.1.12-stable / musl-1.2.5 are the extraction dirs
    TMUX_SRC="$WORK/src/tmux-$TMUX_VERSION"
    LE_SRC="$WORK/src/libevent-$LIBEVENT_VERSION"
    MUSL_SRC="$WORK/src/musl-$MUSL_VERSION"
    [ -d "$TMUX_SRC" ] || die "tmux source dir not found: $TMUX_SRC"
    [ -d "$LE_SRC" ]   || die "libevent source dir not found: $LE_SRC"
}

# ---------------------------------------------------------------------- sysroot
make_sysroot() {
    say "assembling the sysroot (musl headers + Darwin ABI overlay)"
    rm -rf "$SYSROOT"; mkdir -p "$SYSROOT/usr/include" "$SYSROOT/usr/lib"

    cp -r "$MUSL_SRC/include/." "$SYSROOT/usr/include/"
    cp -r "$MUSL_SRC/arch/generic/." "$SYSROOT/usr/include/" 2>/dev/null || true
    cp -r "$MUSL_SRC/arch/$MUSL_ARCH/." "$SYSROOT/usr/include/" 2>/dev/null || true

    # generated bits
    mkdir -p "$SYSROOT/usr/include/bits"
    sed -f "$MUSL_SRC/tools/mkalltypes.sed" \
        "$MUSL_SRC/arch/$MUSL_ARCH/bits/alltypes.h.in" "$MUSL_SRC/include/alltypes.h.in" \
        > "$SYSROOT/usr/include/bits/alltypes.h"
    cp "$MUSL_SRC/arch/$MUSL_ARCH/bits/syscall.h.in" "$SYSROOT/usr/include/bits/syscall.h"
    sed -n 's/__NR_/SYS_/p' "$MUSL_SRC/arch/$MUSL_ARCH/bits/syscall.h.in" \
        >> "$SYSROOT/usr/include/bits/syscall.h"

    # everything we had to correct for the Darwin ABI wins over the above
    cp -r "$here/sysroot-overlay/usr/include/." "$SYSROOT/usr/include/"
    echo "    headers: $(find "$SYSROOT/usr/include" -name '*.h' | wc -l)"
}

get_ncurses_headers() {
    say "obtaining ncurses headers (tmux links against the device's ncurses)"
    mkdir -p "$DHDR"
    if [ -n "$DEVICE" ]; then
        ssh -o BatchMode=yes "$DEVICE" \
            'cd /usr/include && tar cf - ncurses.h curses.h term.h ncurses_dll.h \
                nc_tparm.h termcap.h unctrl.h eti.h panel.h menu.h form.h \
                ncursesw 2>/dev/null' \
            > "$DHDR/ncurses-headers.tar" || die "could not read headers from $DEVICE"
        tar xf "$DHDR/ncurses-headers.tar" -C "$SYSROOT/usr/include"
        ssh -o BatchMode=yes "$DEVICE" 'cat /usr/lib/libncursesw.5.dylib' \
            > "$WORK/libncursesw.5.dylib" || die "could not read libncursesw from $DEVICE"
    else
        die "set DEVICE=<ssh host of the iPad> (its ncurses headers and dylib are needed)"
    fi
    NCDYLIB="$WORK/libncursesw.5.dylib"
    [ -s "$NCDYLIB" ] || die "empty libncursesw"
    echo "    ncurses headers + $(basename "$NCDYLIB") ($(wc -c < "$NCDYLIB") bytes)"
}

export_cc() {
    export IOS_SYSROOT="$SYSROOT"
    export IOS_LD64="$LD64"
    export IOS_STUBDIR="$STUBDIR"
    export IOS_DYLIBS="$NCDYLIB"
    export IOS_PREFIX="$PREFIX"
    export IOS_LD_LIBRARY_PATH="$LD64_LIBS"
    export LLVM_AR
    export CC="$here/tools/cc-wrapper.sh"
    export AR="$here/tools/darwin-ar"
    export RANLIB="$here/tools/darwin-ranlib"
    export CPPFLAGS="-I$SYSROOT/usr/include -I$PREFIX/include"
    export CFLAGS="-O2 $CPPFLAGS"
    export LDFLAGS="-L$PREFIX/lib"
    mkdir -p "$STUBDIR"
    : > "$STUBDIR/libSystem.tbd"
    printf -- "--- !tapi-tbd-v3\narchs: [ %s ]\nplatform: ios\ninstall-name: '/usr/lib/libSystem.B.dylib'\ncurrent-version: 1311.60.2\nexports:\n  - archs: [ %s ]\n    symbols: [ _placeholder ]\n...\n" \
        "$ARCH" "$ARCH" > "$STUBDIR/libSystem.tbd"
}

# -------------------------------------------------------------------- libevent
build_libevent() {
    say "building libevent $LIBEVENT_VERSION for $ARCH"
    cd "$LE_SRC"
    source "$here/patches/fixups.sh"
    fix_libevent_sources "$LE_SRC"
    make distclean >/dev/null 2>&1 || true
    ./configure --host=$ARCH-apple-darwin --prefix="$PREFIX" \
        --disable-shared --enable-static --disable-openssl \
        --disable-libevent-regress --disable-samples --disable-libevent-install \
        >/dev/null
    # libevent's configure output cannot describe this target correctly
    cp "$here/patches/event-config.h" include/event2/event-config.h
    make -j"$(nproc)" >/dev/null
    mkdir -p "$PREFIX/lib" "$PREFIX/include/event2"
    cp .libs/libevent*.a "$PREFIX/lib/"
    # tmux >= 3.8 uses the legacy <event.h> API, so install the wrapper
    # headers too (they only pull in the event2/ ones above).
    cp include/event.h include/evdns.h include/evhttp.h include/evrpc.h \
       include/evutil.h "$PREFIX/include/"
    cp include/event2/*.h "$PREFIX/include/event2/"
    echo "    libs: $(ls "$PREFIX/lib" | tr '\n' ' ')"
}

# ------------------------------------------------------------------------ tmux
configure_tmux() {
    cd "$TMUX_SRC"
    source "$here/patches/fixups.sh"
    fix_tmux_sources "$TMUX_SRC"
    make distclean >/dev/null 2>&1 || true
    ./configure --host=$ARCH-apple-darwin --build="$(cc -dumpmachine)" \
        --prefix="$PREFIX" --disable-utf8proc --disable-jemalloc \
        LIBEVENT_CFLAGS="-I$PREFIX/include" LIBEVENT_LIBS="-L$PREFIX/lib -levent" \
        LIBEVENT_CORE_CFLAGS="-I$PREFIX/include" LIBEVENT_CORE_LIBS="-L$PREFIX/lib -levent" \
        NCURSES_CFLAGS="-I$SYSROOT/usr/include -I$SYSROOT/usr/include/ncursesw" \
        NCURSES_LIBS="-lncursesw" \
        LIBNCURSES_CFLAGS="-I$SYSROOT/usr/include -I$SYSROOT/usr/include/ncursesw" \
        LIBNCURSES_LIBS="-lncursesw" >/dev/null
    # Nothing here should still be missing at this point; fail loudly if so.
    [ -f "$TMUX_SRC/Makefile" ] || die "tmux configure did not produce a Makefile"
    fix_tmux_makefile "$TMUX_SRC" "$NCDYLIB"
    echo "    configure OK"
}

# A first link always succeeds because undefined symbols are allowed.  Collect
# them, declare them in libSystem.tbd, then relink so dyld binds them two-level
# (this is what stops the libgcc_s re-export failure on iOS 10).
generate_stub_and_relink() {
    cd "$TMUX_SRC"
    local undef nc
    undef="$WORK/undefined.txt"; nc="$WORK/ncurses-symbols.txt"
    "$LLVM_NM" -u tmux 2>/dev/null | awk '{print $NF}' | sort -u > "$undef"
    "$LLVM_NM" -gU "$NCDYLIB" 2>/dev/null | awk '{print $NF}' | sort -u > "$nc"
    grep -vxF -f "$nc" "$undef" | grep -E '^_' > "$WORK/system-symbols.txt"
    python3 - "$ARCH" "$WORK/system-symbols.txt" > "$STUBDIR/libSystem.tbd" <<'PY'
import sys
arch, path = sys.argv[1], sys.argv[2]
syms = [l.strip() for l in open(path) if l.strip()]
print("--- !tapi-tbd-v3")
print("archs:           [ %s ]" % arch)
print("platform:        ios")
print("install-name:    '/usr/lib/libSystem.B.dylib'")
print("current-version: 1311.60.2")
print("exports:")
print("  - archs:           [ %s ]" % arch)
print("    symbols:         [ %s ]" % ", ".join(syms))
print("    objc-classes:    []")
print("    objc-ivars:      []")
print("    weak-def-symbols: []")
print("    thread-local-symbols: []")
print("...")
PY
    echo "    libSystem.tbd declares $(wc -l < "$WORK/system-symbols.txt") symbols"
    rm -f tmux && make -j"$(nproc)" >/dev/null
}

build_tmux() {
    say "building tmux $TMUX_VERSION for $ARCH"
    configure_tmux
    cd "$TMUX_SRC" && make -j"$(nproc)" >/dev/null
    generate_stub_and_relink
    mkdir -p "$OUT"
    cp tmux "$OUT/tmux-$TMUX_VERSION-$ARCH"
    echo "    binary: $OUT/tmux-$TMUX_VERSION-$ARCH"
    file "$OUT/tmux-$TMUX_VERSION-$ARCH" 2>/dev/null | sed 's/^/    /' || true
}

summary() {
    say "done"
    cat <<EOF
    binary   : $OUT/tmux-$TMUX_VERSION-$ARCH
    sysroot  : $SYSROOT
    arch     : $ARCH, min iOS $TARGET_IOS
    links    : libSystem + the device's libncursesw

    Install on the device:
        scp $OUT/tmux-$TMUX_VERSION-$ARCH root@<ipad>:/var/mobile/tmux
        ssh root@<ipad> 'chmod +x /var/mobile/tmux && ldid -S /var/mobile/tmux'
        ssh root@<ipad> '/var/mobile/tmux -V'
EOF
}

main() {
    preflight
    fetch_tmux_version
    fetch_sources
    make_sysroot
    get_ncurses_headers
    export_cc
    build_libevent
    build_tmux
    summary
}
main "$@"
