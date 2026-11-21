#!/bin/bash
# tools/bootstrap-toolchain.sh -- build ~/ios-tool (the cross toolchain this
# repo builds everything with) from scratch, in idempotent stages.
#
# The toolchain this script assembles (see docs/toolchain.md for usage):
#
#   Ubuntu clang (apt)                -- the compiler; Darwin target support
#                                        is built in, no Apple download needed
#   cctools-port ld64 (ELF, Linux)    -- the linker; from conda-forge's
#                                        cross toolchain packages, which also
#                                        carry the three shared objects ld64
#                                        dlopens/needs: libtapi, libdispatch,
#                                        libBlocksRuntime (without them ld64
#                                        prints "libBlocksRuntime.so not
#                                        found"; toolchain.md section 1)
#   tapi 1600.0.11.8                  -- text-based dylib stubs toolchain libs
#   ldid                              -- ad-hoc pseudo-signing
#   iPhoneOS10.3.sdk                  -- public Apple headers, from the
#                                        xybp888/iOS-SDKs mirror
#   libSystem.tbd + cxx-wrapper.sh    -- this repo's own pieces
#                                        (tools/sysroot/libSystem.tbd is the
#                                        device-10.3.3-aligned stub; the SDK's
#                                        own libSystem.tbd is the 10.3 GM cut
#                                        and NOT what the builds link against)
#
# Usage:
#   tools/bootstrap-toolchain.sh                     # all stages
#   tools/bootstrap-toolchain.sh --stage=3           # from stage 3
#   tools/bootstrap-toolchain.sh --check-only        # verify an existing tree
#   tools/bootstrap-toolchain.sh --prefix=/opt/ios-tool
#
# Stages are skipped when their output already exists (pass --force to redo).
# Downloads land in $BOOTSTRAP_CACHE (default <prefix>/bootstrap-cache) so a
# re-run never re-downloads.
set -euo pipefail

PREFIX="${HOME}/ios-tool"
FROM_STAGE=0
CHECK_ONLY=0
FORCE=0
for a in "$@"; do
    case "$a" in
        --prefix=*)  PREFIX="${a#*=}" ;;
        --stage=*)   FROM_STAGE="${a#*=}" ;;
        --check-only) CHECK_ONLY=1 ;;
        --force)     FORCE=1 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done
CACHE="${BOOTSTRAP_CACHE:-$PREFIX/bootstrap-cache}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$PREFIX" "$CACHE"
cd "$PREFIX"

log() { printf '\n==> [stage %s] %s\n' "$1" "$2"; }
skip() { printf '    already present, skipped (--force to redo)\n'; }

# ---------------------------------------------------------------- stage 0 --
stage0_deps() {
    log 0 "host dependencies (apt)"
    # Check per-package, not "is clang present": GitHub runners and many dev
    # boxes preinstall clang/llvm, and an early return here silently skips
    # the rest (libplist-dev was lost exactly this way -- CI run 44873894283).
    local missing=""
    for p in clang llvm lld cmake ninja-build git xz-utils zstd patch unzip \
             libplist-dev autoconf automake libtool-bin pkg-config make \
             perl python3 file curl ca-certificates; do
        dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
    done
    if [ -z "$missing" ]; then
        echo "    all present (clang $(clang --version | head -1))"
        return
    fi
    echo "    installing:$missing"
    sudo apt-get update -qq
    # shellcheck disable=SC2086
    sudo apt-get install -y -qq $missing
}

# ------------------------------------------------------------- conda pieces --
# The four conda-forge cross-toolchain packages, pinned by sha256.  These
# checksums were computed from the copies this toolchain was actually built
# with, so the pins are authoritative even before the first fresh download.
CONDA_URL_BASE="https://conda.anaconda.org/conda-forge/linux-64"
CONDA_PKGS=(
    "cctools_osx-64-1030.6.3-llvm21_1_hfdf8bbe_6.conda|54865fc91f9af418d885a34830c7d088e7db27706787e599f4fe54c5e26fe183"
    "ld64_osx-64-956.6-llvm21_1_h7ca6327_6.conda|9617de7ecf5eba13938dc240e155908884914218c50467e9b864fd1314914650"
    "libdispatch-6.4.0-h420ff9e_0.conda|dac1ff75f27cf45f630af62f0e25c5290745c2e451e3f3edd29bb9b1604afd02"
    "tapi-1600.0.11.8-hfd2156b_4.conda|cf74aadd350be2e7c0f017f067b541e00c1f41eb2dc96d1a221400bc8e937a7f"
)

fetch() { # fetch <url> <sha256> <dest>
    local url="$1" sha="$2" dest="$3"
    if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c --quiet 2>/dev/null; then
        echo "    cached ok: $dest"; return
    fi
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$dest.part" "$url"
    echo "$sha  $dest.part" | sha256sum -c --quiet \
        || { echo "sha256 mismatch for $url" >&2; rm -f "$dest.part"; exit 1; }
    mv "$dest.part" "$dest"
}

# unpack a conda v2 package (.conda = zip{pkg-*.tar.zst, info-*.tar.zst})
unpack_conda() { # unpack_conda <file.conda> <dest-dir>
    local f="$1" dest="$2"
    mkdir -p "$dest"
    local zst; zst="$(unzip -l "$f" | awk '/pkg-.*\.tar\.zst/{print $4; exit}')"
    unzip -o -q "$f" "$zst" -d "$dest/.tmp"
    zstd -dc "$dest/.tmp/$zst" | tar -x -C "$dest"
    rm -rf "$dest/.tmp"
}

stage1_cctools() {
    log 1 "cctools-port ld64 + tapi + libdispatch (conda-forge cross packages)"
    [ -x "$PREFIX/x-ld64/bin/x86_64-apple-darwin13.4.0-ld" ] && [ "$FORCE" = 0 ] && { skip; return; }
    for row in "${CONDA_PKGS[@]}"; do
        local fn="${row%%|*}" sha="${row##*|}"
        fetch "$CONDA_URL_BASE/$fn" "$sha" "$CACHE/$fn"
    done
    unpack_conda "$CACHE/cctools_osx-64-1030.6.3-llvm21_1_hfdf8bbe_6.conda" "$PREFIX/x-cctools"
    unpack_conda "$CACHE/ld64_osx-64-956.6-llvm21_1_h7ca6327_6.conda"       "$PREFIX/x-ld64"
    unpack_conda "$CACHE/libdispatch-6.4.0-h420ff9e_0.conda"                "$PREFIX/x-libdispatch"
    unpack_conda "$CACHE/tapi-1600.0.11.8-hfd2156b_4.conda"                 "$PREFIX/x-tapi"
    # the ld64 binary ships as bin/ld inside the package; expose it under the
    # triple-prefixed name every build.sh and toolchain.md section 1 refers to
    if [ ! -e "$PREFIX/x-ld64/bin/x86_64-apple-darwin13.4.0-ld" ]; then
        cp -a "$PREFIX/x-ld64/bin/ld" "$PREFIX/x-ld64/bin/x86_64-apple-darwin13.4.0-ld"
    fi
}

stage2_ldid() {
    log 2 "ldid (ad-hoc pseudo-signer)"
    [ -x "$PREFIX/bin/ldid" ] && [ "$FORCE" = 0 ] && { skip; return; }
    # pinned to the tag the working toolchain was built from -- never a
    # branch archive: master.tar.gz bytes drift, and a sha256 pin against a
    # moving target fails exactly like it did in CI run 44872564758.
    fetch "https://github.com/ProcursusTeam/ldid/archive/refs/tags/v2.1.5-procursus7.tar.gz" \
          "04e461c6f02765e48fc9cc0b68d4dc353a9c46bc1c4d8bac0695509d1af1ff5e" \
          "$CACHE/ldid-2.1.5-procursus7.tar.gz"
    mkdir -p "$PREFIX/ldid-src"
    tar -xzf "$CACHE/ldid-2.1.5-procursus7.tar.gz" -C "$PREFIX/ldid-src"
    ( cd "$PREFIX"/ldid-src/ldid-2.1.5-procursus7
      make -j"$(nproc)" ldid >/dev/null
      mkdir -p "$PREFIX/bin" && cp -a ./ldid "$PREFIX/bin/ldid" )
    # ldid has no --version flag (it prints usage); running it bare is the
    # executable check.  The real signing path is exercised in the smoke stage.
    "$PREFIX/bin/ldid" 2>&1 | grep -q 'Usage:' && echo "    ldid installed"
}

stage3_sdk() {
    log 3 "iPhoneOS10.3.sdk (public headers, xybp888/iOS-SDKs master)"
    if [ -f "$PREFIX/iPhoneOS10.3.sdk/usr/include/stdio.h" ] && [ "$FORCE" = 0 ]; then
        skip; return
    fi
    # The mirror organizes every SDK as a plain directory on master -- no
    # per-SDK tags, no release assets -- so the cheap way to fetch one
    # directory is a blob-filtered sparse clone.  A directory asset has no
    # single sha256 to pin; the source commit is recorded instead, and the
    # smoke stage validates that the headers actually compile.
    if [ ! -d "$CACHE/iOS-SDKs/.git" ]; then
        git clone --filter=blob:none --sparse --depth 1 \
            https://github.com/xybp888/iOS-SDKs "$CACHE/iOS-SDKs"
    fi
    ( cd "$CACHE/iOS-SDKs" && git sparse-checkout set iPhoneOS10.3.sdk )
    rm -rf "$PREFIX/iPhoneOS10.3.sdk"
    cp -a "$CACHE/iOS-SDKs/iPhoneOS10.3.sdk" "$PREFIX/"
    git -C "$CACHE/iOS-SDKs" rev-parse HEAD > "$PREFIX/.sdk-source-commit"
    [ -f "$PREFIX/iPhoneOS10.3.sdk/usr/include/stdio.h" ] \
        || { echo "SDK layout unexpected" >&2; exit 1; }
    echo "    sdk at commit $(cat "$PREFIX/.sdk-source-commit")"
}

stage4_stubs() {
    log 4 "libSystem.tbd + cxx-wrapper (this repo's pieces)"
    local repo="$REPO_ROOT"
    [ -f "$PREFIX/libSystem.tbd" ] && [ "$FORCE" = 0 ] && { skip; return; }
    cp -a "$repo/tools/sysroot/libSystem.tbd" "$PREFIX/libSystem.tbd"
    cp -a "$repo/tools/cxx-wrapper.sh"        "$PREFIX/cxx-wrapper.sh"
    chmod +x "$PREFIX/cxx-wrapper.sh"
    # libcxx15-headers: C++ headers matched to the device's libc++ 6.0.1 ABI
    # (8 MB, extracted from the device).  Not automatable from the repo; if
    # missing, C++ ports need them copied from an existing toolchain tree.
    if [ ! -d "$PREFIX/libcxx15-headers" ]; then
        echo "    NOTE: $PREFIX/libcxx15-headers missing -- C++ ports need the"
        echo "          device-vintage libc++ headers copied in by hand"
    fi
}

stage5_smoke() {
    log 5 "smoke: hello.c -> armv7 Mach-O"
    local repo="$REPO_ROOT"
    export IOS_SYSROOT="$PREFIX/iPhoneOS10.3.sdk"
    export IOS_LD64="$PREFIX/x-ld64/bin/x86_64-apple-darwin13.4.0-ld"
    export IOS_STUBDIR="$PREFIX"
    export LD_LIBRARY_PATH="$PREFIX/x-libdispatch/lib:$PREFIX/x-tapi/lib"
    # ld64's own shared objects must resolve before anything else runs
    if ldd "$IOS_LD64" 2>/dev/null | grep -q "not found"; then
        echo "ld64 has unresolved shared objects:" >&2
        ldd "$IOS_LD64" 2>&1 | grep "not found" >&2
        exit 1
    fi
    cat > "$CACHE/hello.c" <<'EOF'
#include <stdio.h>
int main(void) { puts("hello armv7"); return 0; }
EOF
    local out="$CACHE/hello-armv7"
    "$repo/tools/cc-wrapper.sh" "$CACHE/hello.c" -o "$out"
    file "$out" | grep -q "Mach-O.*arm" \
        || { echo "smoke output is not arm Mach-O:" >&2; file "$out" >&2; exit 1; }
    # the deployment tripwire of this repo starts with a valid ad-hoc
    # signature; exercise it here so "toolchain ready" means "ldid works too"
    local LDID="$PREFIX/bin/ldid"
    [ -x "$LDID" ] || LDID=ldid
    "$LDID" -S "$out"
    "$LDID" -e "$out" >/dev/null
    echo "    $(file "$out" | cut -d: -f2- | sed 's/^ *//') + ad-hoc signed"
    echo
    echo "==> toolchain ready.  For build shells export (toolchain.md section 1):"
    cat <<EOF
    export IOS_SYSROOT=$PREFIX/iPhoneOS10.3.sdk
    export IOS_STUBDIR=$PREFIX
    export IOS_LD64=$PREFIX/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
    export LD_LIBRARY_PATH=$PREFIX/x-libdispatch/lib:$PREFIX/x-tapi/lib
EOF
}

# --check-only: verify an existing tree without building anything
if [ "$CHECK_ONLY" = 1 ]; then
    rc=0
    for p in \
        "$PREFIX/x-ld64/bin/x86_64-apple-darwin13.4.0-ld" \
        "$PREFIX/iPhoneOS10.3.sdk/usr/include/stdio.h" \
        "$PREFIX/libSystem.tbd" \
        "$PREFIX/cxx-wrapper.sh"; do
        if [ -e "$p" ]; then echo "ok      $p"; else echo "MISSING $p"; rc=1; fi
    done
    command -v ldid >/dev/null || [ -x "$PREFIX/bin/ldid" ] \
        && echo "ok      ldid" || { echo "MISSING ldid"; rc=1; }
    exit "$rc"
fi

case "$FROM_STAGE" in
    0) stage0_deps ;;&
    0|1) stage1_cctools ;;&
    0|1|2) stage2_ldid ;;&
    0|1|2|3) stage3_sdk ;;&
    0|1|2|3|4) stage4_stubs ;;&
    *) stage5_smoke ;;
esac
echo "==> bootstrap complete"
