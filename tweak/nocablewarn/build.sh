#!/bin/bash
# Build the nocablewarn tweak deb.
#   out: com.hesper.nocablewarn_<ver>_iphoneos-arm.deb
#
# Requires: the cross toolchain (see the top-level build.sh prerequisites)
# and host ldid.  The hook target class is hard-coded (SBUIController): an
# earlier build scanned all classes with objc_copyClassList, which aborted
# the ObjC runtime on this device.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
V="${V:-1.0-1}"
SYSROOT="${SYSROOT:-$here/../tmp/sysroot}"
[ -d "$SYSROOT/usr/include" ] || SYSROOT="${SYSROOT_OVERRIDE:-/home/hesper/ios-tool/tmux-minimal-build/sysroot}"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/DEBIAN" "$work/Library/MobileSubstrate/DynamicLibraries"

LD_LIBRARY_PATH="${LD64_LIBS:-}" IOS_SYSROOT="$SYSROOT" \
IOS_LD64="${LD64:?set LD64 to the cctools-port ld}" \
IOS_STUBDIR="${IOS_STUBDIR:-$here/../..}" \
"$here/../tools/cc-wrapper.sh" -dynamiclib -undefined dynamic_lookup \
    -o "$work/tweak.dylib" "$here/tweak.c"
ldid -S "$work/tweak.dylib"

cp "$here/control" "$work/DEBIAN/control"
sed -i "s/^Version: .*/Version: $V/" "$work/DEBIAN/control"
cp "$here/filter.plist" "$work/Library/MobileSubstrate/DynamicLibraries/nocablewarn.plist"
install -m 0755 "$work/tweak.dylib" "$work/Library/MobileSubstrate/DynamicLibraries/nocablewarn.dylib"

deb="$here/../out/com.hesper.nocablewarn_${V}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$work" "$deb" >/dev/null
echo "==> $deb"
