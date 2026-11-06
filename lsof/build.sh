#!/bin/bash
# Build lsof 4.99.7 for armv7 iOS 10.x on Linux.
#
# lsof is the rare port that is *easier* than its age suggests, and the
# reason decides the whole approach:
#
#   * the Darwin dialect of lsof >= 4.80 is libproc-based -- it talks to the
#     kernel through proc_listpids()/proc_pidinfo()/proc_pidfdinfo(), the
#     same interface ps uses.  The ancient 4.78 that ships in jailbreak
#     images predates that and parses `struct kinfo_proc` by hand; on iOS 10
#     the layout no longer matches and every PID fails with
#     "Cannot allocate memory".  Nothing can fix 4.78; 4.99.7 needs no
#     kernel-side work at all.
#   * everything the build needs is headers, and specifically ONE header:
#     sys/proc_info.h, which defines the PROC_PID* flavors and the structs
#     the kernel copies into the caller's buffer.  The sysroot ships it --
#     verbatim from the xnu tag matching iOS 10.3.x (xnu-3789.70.16) -- and
#     libproc.h now includes it rather than hand-declaring a subset.
#
# Getting sys/proc_info.h exactly right is the whole game.  Its structs are
# kernel ABI: a field a few bytes off produces silently wrong output rather
# than a compile error, which is precisely the disease the old 4.78 died of.
# Do not hand-edit it; copy it from the xnu tag matching the device kernel
# (uname -v) -- see ../sysroot-overlay/usr/include/sys/proc_info.h.
#
# Usage:
#   LD64=.../x86_64-apple-darwin13.4.0-ld LD64_LIBS=... ./build.sh
#   [LSOF_SRC=/path/to/lsof-4.99.7] ./build.sh   # reuse an existing tree
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
LSOF_VERSION="${LSOF_VERSION:-4.99.7}"
SRC="${LSOF_SRC:-$HOME/ios-tool/lsof-src/lsof-$LSOF_VERSION}"

# Fetch the source if it is not there yet.  raw.githubusercontent.com is
# unreliable from this host; the codeload tarball over github.com works.
if [ ! -d "$SRC" ]; then
    echo "==> fetching lsof $LSOF_VERSION"
    mkdir -p "$(dirname "$SRC")"
    curl -L --fail -o /tmp/lsof.tar.gz \
        "https://github.com/lsof-org/lsof/archive/refs/tags/$LSOF_VERSION.tar.gz"
    tar xzf /tmp/lsof.tar.gz -C "$(dirname "$SRC")"
    rm -f /tmp/lsof.tar.gz
fi
[ -d "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
cd "$SRC"

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="${LD64_LIBS:-}:${LD_LIBRARY_PATH:-}"

# Apply the dialect patches.  Both are idempotent by marker: lsof ships as a
# tarball, the tree is reused across builds, and `patch` would refuse a
# second application.
[ -f lib/dialects/darwin/dlsof.h ] || { echo "unexpected source layout" >&2; exit 1; }
grep -q "iOS 10.3 cross build" lib/dialects/darwin/dlsof.h || \
    patch -p1 < "$here/patches/010-dlsof-h-drop-rpc-attr.patch"
grep -q "HASNORPC_H" lib/dialects/darwin/machine.h || \
    patch -p1 < "$here/patches/020-machine-h-ios.patch"

# Configure.  Everything is driven through the environment because the old
# lsof Configure script predates autoconf:
#   * LSOF_VSTR is the kernel release the *device* reports (uname -r); the
#     16.* case maps it to DARWINV=1600, and -DDARWINV=1600 selects the
#     right conditionals for an xnu-3789 kernel.  Hardcode nothing.
#   * DARWIN_BASE=libproc forces the libproc dialect (the default for
#     Darwin >= 8 anyway; stating it keeps the configure output honest).
#   * LSOF_AR/LSOF_RANLIB must be the Darwin ar/ranlib -- GNU ar archives
#     are unreadable by ld64 (see ../tools/).
export CONFIG_SITE=""   # lsof's Configure does not use config.site; listed
                        # here so a stray export cannot pretend it did.
LSOF_CC="$root/tools/cc-wrapper.sh" \
LSOF_VSTR="16.7.0" \
LSOF_INCLUDE="$IOS_SYSROOT/usr/include" \
DARWIN_BASE="libproc" \
LSOF_AR="$root/tools/darwin-ar cr" \
LSOF_RANLIB="$root/tools/darwin-ranlib" \
./Configure -n darwin >/dev/null

# The darwin branch appends -lcurses unconditionally.  iOS has no curses and
# nothing in the libproc dialect calls it; the wrapper would hand -lcurses to
# ld64 and fail the link on a missing library.
sed -i 's/ -lcurses//' Makefile lib/Makefile

# -n avoids the AFS/customization/inventory checks; -j is safe because the
# generated Makefiles have real dependencies.
make -j"$(nproc)" >/dev/null

# The artifact is deliberately unsigned -- make-deb.sh signs the copy it
# stages.  An unsigned binary that reaches the device dies with SIGKILL and
# no output before main(); that is the documented signing failure mode, and
# the packaging scripts now assert a signature instead of hoping for one.
[ -f lsof ] || { echo "lsof was not built" >&2; exit 1; }
mkdir -p "$root/out"
cp lsof "$root/out/lsof-$LSOF_VERSION-armv7"
echo "==> $root/out/lsof-$LSOF_VERSION-armv7"
echo "    run with sudo to see other users' processes; as mobile you only"
echo "    see your own (libproc enforces it, same as macOS)"
