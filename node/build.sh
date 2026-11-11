#!/bin/bash
# Build Node.js v22.23.4 for armv7 iOS 10.x on Linux.
#
# STATUS: this script is *prepared*, not yet proven.  The port is being
# driven in parallel in ~/scratch/node-research/node-v22.23.4/, where the
# tree is configured and about 90% linked as of 2026-11-08.  Nothing below
# has completed an end-to-end run from a clean checkout.  Where a step is
# known to be load-bearing that is stated; where it is a placeholder that is
# stated too.  Do not read "exit 0" here as "Node runs on the device".
#
# ---------------------------------------------------------------------------
# Why this port is different from every other one in this repo
# ---------------------------------------------------------------------------
#
# Every other port (tmux, curl, lsof, dropbear, openssh) is a C program that
# builds against the hand-made sysroot and links against the device's
# libSystem.  Node is a C++20 program with an embedded V8, and the shape of
# the problem follows from two facts:
#
#   1. There is no Apple SDK on this host.  We have a sysroot *overlay*:
#      87 hand-written/copied Darwin headers layered over a musl Linux
#      sysroot (see ../sysroot-overlay/ and README "The sysroot overlay").
#      That is enough to compile, and it is emphatically not enough to run
#      Node's build system unmodified.
#
#   2. The target cannot execute generated code.  iOS 10 on a 32-bit device
#      enforces W^X hard enough that V8's JIT allocation is killed by the
#      kernel, so Node must run jitless.  That is an *execution* concern
#      (see jitless-wrap.sh and VERIFY.md), not a build concern -- we build
#      a normal V8 and pass --jitless at runtime.
#
# ---------------------------------------------------------------------------
# What is actually required vs. what is skipped, and why
# ---------------------------------------------------------------------------
#
# REQUIRED (the build does not work without these):
#
#   * configure.py with --dest-os=ios.  gyp's `OS` variable is what the
#     whole tree conditions on, and common.gypi has a dedicated OS=="ios"
#     block (C++20, NODE_MACOS_KEYCHAIN_DISABLED, NO_RECVMMSG, the
#     libdispatch include path).  gyp does NOT follow --dest-cpu/--dest-os,
#     so the cross values must be stated twice: once to configure and once
#     in GYP_DEFINES so node.gyp/common.gypi actually see them.
#
#   * CC/CXX pointed at the wrapper in ../tools/cc-wrapper.sh, plus
#     IOS_SYSROOT / IOS_LD64 / IOS_STUBDIR in the environment.  The wrapper
#     translates a clang-ish command line into a cctools ld64 link; it is
#     the only linker here that emits Mach-O armv7.
#
#   * --openssl-no-asm.  OpenSSL's armv7 assembly uses NEON registers the
#     S5L8950X has, but more importantly the perlasm output is not ABI-clean
#     under this sysroot.  The C fallback is what every other port here
#     already uses for the same reason; it costs throughput and nothing
#     else.  Verified on device for OpenSSL 4.0.3 (~36 MB/s AES).
#
#   * --without-intl (i.e. --with-intl=none).  full-icu needs ICU data and
#     a working ICU build; the device has ~5.4 GB free and Node is being
#     installed for scripting, not for Intl.  Consequence: `Intl` is
#     undefined and `toLocaleString` falls back.  Documented, deliberate.
#
#   * --without-npm (see below -- npm is packaged separately, not built in).
#
#   * The sysroot overlay must already contain the V8/libuv/c-ares/ICU-adjacent
#     headers listed in ../DEVICE.md §11.1.  If `mach/semaphore.h` or
#     `os/availability.h` is missing the failure is a compile error inside
#     V8, not a configure error, so this script only checks for a couple of
#     sentinels and says so.
#
# OPTIONAL / SKIPPED, with the reason:
#
#   * `make install` is NOT used.  tools/install.py installs the whole
#     runtime (headers, npm, corepack, lib/node_modules) into $PREFIX.  We
#     want one signed binary at a fixed path, and make-deb.sh does the
#     staging -- packaging by hand keeps the signature step under our
#     control.  PREFIX is set anyway so configure's generated config.mk is
#     honest about intent.
#
#   * --without-node-snapshot: a startup snapshot is built at *build* time
#     by running a host node on the target's bytecode.  With want_separate_
#     host_toolset=1 that needs a working host node of the exact same
#     version, which is a bootstrap dependency we do not want.  Without a
#     snapshot Node deserializes its builtins from the compiled-in array
#     literals instead; startup is slower, correctness is unaffected.
#
#   * --without-amaro, --without-sqlite, --without-inspector are NOT passed
#     by default.  They are the knobs to reach for if the link grows too
#     large or a component fails to build, not decisions made up front.
#     FLAGS= in the environment appends to the configure line for exactly
#     this kind of experiment.
#
#   * There is no "apply patches" step here yet.  The in-flight port has
#     been editing the tree directly (config.gypi, node.gyp, common.gypi
#     already differ from the release tarball).  Those edits MUST be turned
#     into patches under node/patches/ before this script can reproduce the
#     build from a clean fetch; until then this script is honest about
#     consuming a tree that someone else configured.
#
#   * ldid -S at the end signs the *staged output*, matching the rule in
#     DEVICE.md §10: sign once on the host, assert with ldid -e, never sign
#     twice.  The artifact in out/ from this script IS signed; make-deb.sh
#     re-signs its own copy, which is the same single-sign-per-file rule
#     (each file is signed exactly once).
#
# Usage:
#   LD64=/path/to/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
#   LD64_LIBS=/path/to/x-libdispatch/lib \
#   ./node/build.sh
#
#   NODE_SRC=/path/to/node-v22.23.4 ./node/build.sh   # reuse an existing tree
#   JOBS=4 ./node/build.sh                            # cap parallelism
#   FLAGS="--without-inspector" ./node/build.sh       # extra configure flags
#   SKIP_CONFIGURE=1 ./node/build.sh                  # reuse existing config.gypi
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

NODE_VERSION="${NODE_VERSION:-22.23.4}"
SRC="${NODE_SRC:-$HOME/scratch/node-research/node-v$NODE_VERSION}"
OUT_BIN="$root/out/node-$NODE_VERSION-armv7"

# --------------------------------------------------------------- toolchain --
# Same contract as every other build.sh here.  IOS_SYSROOT is the synced
# copy of the overlay (tmp/sysroot), not the overlay itself -- the overlay
# is the source of truth and tmp/ is the build view of it.
export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
export IOS_LD64="${IOS_LD64:-${LD64:-}}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export LD_LIBRARY_PATH="${LD64_LIBS:-}:${LD_LIBRARY_PATH:-}"

[ -d "$IOS_SYSROOT/usr/include" ] || {
    echo "no sysroot at $IOS_SYSROOT/usr/include -- run tmux/build.sh to sync" >&2
    exit 1
}
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || {
    echo "set LD64 (or IOS_LD64) to the cctools ld64 binary" >&2
    exit 1
}

# Two sentinels out of the ~87 overlay headers.  They are chosen because
# each one is reached from a *different* corner of the tree (V8 base vs.
# libuv) and both failures are otherwise reported deep inside a compile
# error rather than as "your sysroot is stale".  This is a smoke check, not
# a completeness check -- see DEVICE.md §11.1 for the real list.
for h in os/availability.h mach/semaphore.h; do
    [ -f "$IOS_SYSROOT/usr/include/$h" ] || {
        echo "sysroot is missing $h -- overlay is stale, re-sync tmp/sysroot" >&2
        exit 1
    }
done

CC_WRAPPER="$root/tools/cc-wrapper.sh"
[ -x "$CC_WRAPPER" ] || { echo "missing $CC_WRAPPER" >&2; exit 1; }

# ------------------------------------------------------------------ source --
# The tarball is 108 MB; raw.githubusercontent is unreliable from this host
# (same note as lsof/build.sh), so nodejs.org over HTTPS is the source.
if [ ! -d "$SRC" ]; then
    echo "==> fetching node v$NODE_VERSION"
    mkdir -p "$(dirname "$SRC")"
    curl -L --fail -o /tmp/node.tar.gz \
        "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION.tar.gz"
    tar xzf /tmp/node.tar.gz -C "$(dirname "$SRC")"
    rm -f /tmp/node.tar.gz
fi
[ -f "$SRC/configure.py" ] || { echo "unexpected source layout in $SRC" >&2; exit 1; }
cd "$SRC"

# --------------------------------------------------------------- configure --
# See the header comment for which of these are load-bearing.  The flags
# that are NOT passed are as deliberate as the ones that are.
export GYP_DEFINES="OS=ios"
export CC="$CC_WRAPPER"
export CXX="$CC_WRAPPER"
export LINK="$CC_WRAPPER"
# gyp invokes `python`; iOS has no python and neither does this build need
# it on the device, but the *host* does.  configure.py itself is python3.
export PYTHON="${PYTHON:-python3}"

if [ "${SKIP_CONFIGURE:-0}" = "1" ]; then
    # Escape hatch for the in-flight tree, which is already configured and
    # whose config.gypi carries hand edits this script does not yet
    # reproduce.  Running configure again would silently discard them.
    [ -f config.gypi ] || { echo "SKIP_CONFIGURE=1 but there is no config.gypi" >&2; exit 1; }
    echo "==> skipping configure (SKIP_CONFIGURE=1), reusing existing config.gypi"
    echo "    NOTE: this is a build of whatever that tree currently contains."
else
    echo "==> configure (dest-os=ios dest-cpu=arm)"
    # --dest-cpu=arm         -> 32-bit arm, and armv7 is what clang emits
    #                           for the -target in the wrapper.
    # --cross-compiling      -> stops configure from probing the *host* for
    #                           target properties (endianness, pointer size,
    #                           and the host-toolset decision).
    # --openssl-no-asm       -> see header.
    # --with-intl=none       -> see header.
    # --without-npm          -> npm ships as its own package; see
    #                           make-deb.sh.  Building it in would put 20 MB
    #                           of JS inside a directory dpkg does not own.
    # --without-node-snapshot-> see header.
    # --prefix=/var/mobile/tools
    #                        -> matches the device convention (DEVICE.md §9:
    #                           /var/mobile/tools holds the installed kit).
    #                           It only lands in the generated config.mk;
    #                           we do not run `make install`.
    # --verbose              -> the command lines end up in out/Makefile,
    #                           which is the only affordable way to debug a
    #                           gyp translation when the wrapper is in play.
    "$PYTHON" ./configure \
        --dest-os=ios \
        --dest-cpu=arm \
        --cross-compiling \
        --openssl-no-asm \
        --with-intl=none \
        --without-npm \
        --without-node-snapshot \
        --prefix=/var/mobile/tools \
        --verbose \
        ${FLAGS:-}
fi

# -------------------------------------------------------------------- make --
# There is no `make -j` safety question here the way there is in lsof:
# gyp emits ninja files or GNU makefiles with real dependencies, and the
# node Makefile is generated.  JOBS exists because this link step is where
# the machine runs out of memory, not because of correctness.
#
# This is the long pole: V8 + Node is ~4000 translation units, and on this
# host the Torque/bytecode generators run first.  Expect tens of minutes.
echo "==> make -j${JOBS:-$(nproc)}"
make -j"${JOBS:-$(nproc)}"

# `make` produces ./node as a symlink into out/Release/node.  Resolve it:
# cp -L below would work either way, but the size check wants a real file.
[ -f out/Release/node ] || {
    echo "out/Release/node was not produced -- the link step did not finish" >&2
    exit 1
}

# -------------------------------------------------------------------- sign --
# DEVICE.md §10: sign ONCE on the host, then assert.  The device kills an
# unsigned Mach-O during exec, before main() -- rc=137, empty stdout and
# stderr, no crash report.  ldid -e exits 0 only when a signature is
# present, so this is an assertion and not a formality; a missing ldid is a
# hard error rather than an `|| true`, which is the failure mode §7/§10
# document at length.
mkdir -p "$root/out"
cp -L out/Release/node "$OUT_BIN"
chmod 0755 "$OUT_BIN"

command -v ldid >/dev/null 2>&1 || {
    echo "ldid is not on PATH -- refusing to hand out an unsigned binary" >&2
    echo "the unsigned artifact is at $OUT_BIN if you want it anyway" >&2
    exit 1
}
ldid -S "$OUT_BIN" || { echo "ldid -S failed for $OUT_BIN" >&2; exit 1; }
ldid -e "$OUT_BIN" >/dev/null 2>&1 || {
    echo "$OUT_BIN carries no signature after ldid -S" >&2
    exit 1
}

# A size sanity check, not a correctness check.  A jitless-capable Node with
# V8, libuv, OpenSSL, c-ares, cares and zlib statically linked is tens of
# megabytes; anything in the low hundreds of KB is a stub or a partial link
# that happened to exit 0.  This threshold is a guess and is labelled as one.
sz=$(stat -c %s "$OUT_BIN")
if [ "$sz" -lt 5000000 ]; then
    echo "WARNING: $OUT_BIN is only $((sz / 1024)) KB -- implausibly small for" >&2
    echo "         a statically-linked Node.  Verify before packaging." >&2
fi

echo "==> $OUT_BIN ($((sz / 1024 / 1024)) MB, signed)"
echo
echo "    NOT VERIFIED: this script has not completed an end-to-end run."
echo "    Next step is node/make-deb.sh, then node/VERIFY.md on the device."
echo "    The binary must be run under node/jitless-wrap.sh -- a bare node"
echo "    will be killed by the kernel at the first JIT allocation."
