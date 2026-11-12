#!/bin/bash
# Build tcpdump 4.99.5 for armv7 iOS 10.x on Linux.
#
# Depends on a libpcap built by ../libpcap/build.sh: tcpdump 4.99.5 has no
# --with-pcap option at all -- it discovers a *local* libpcap build tree
# sitting next to its own source directory (../libpcap-X.Y.Z), so this
# script symlinks the libpcap tree in if it is not already there.
#
# The device-side chain this closes (2026-11-12, all verified live):
#   /dev/bpf0-2 exist and are readable by root -> xnu-3789.70.16 net/bpf.h
#   in the sysroot -> libpcap BPF support -> tcpdump -i en0 -c 3 captured
#   real SSH traffic.  Wi-Fi interfaces refuse promiscuous mode on this
#   device (BIOCPROMISC: Operation not supported on socket) -- tcpdump
#   prints a warning and works anyway.
#
# Walls found on the way (all recorded here so re-builds are boring):
#
#   * sysroot unistd.h declared getopt_long's 4th parameter as
#     `const void *`, while getopt.h correctly says `const struct option *`.
#     Any file including both (tcpdump.c) failed with conflicting types.
#     Fixed in the sysroot header itself (forward-declared struct option).
#   * tcpdump's configure probes `main in -lpcap` style tests through the
#     cc-wrapper, whose link line is `-undefined dynamic_lookup` -- every
#     such probe SUCCEEDS regardless of whether the symbol exists.  The
#     false positives that mattered here: HAVE_PCAP_SET_OPTIMIZER_DEBUG,
#     HAVE_PCAP_SET_PARSER_DEBUG, HAVE_PCAP_FINDALLDEVS_EX and
#     HAVE_PCAP_OPEN are all #define'd in config.h, but none of those
#     symbols exists in libpcap 1.10.5 (pcap_set_*_debug are guarded by
#     BDEBUG, which libpcap's default build #undefs).  tcpdump then calls
#     them and dies at first use with
#       dyld: lazy symbol binding failed: Symbol not found: _pcap_set_optimizer_debug
#     (only on the packet-processing path -- --version and -D run fine,
#     which is exactly what makes this trap nasty).
#     Fix: edit config.h to #undef all four, verified against
#     `llvm-nm libpcap.a` before rebuilding.
#
# Usage:
#   export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot \
#          IOS_STUBDIR=$HOME/ios-tool \
#          IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
#          LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
#   ./tcpdump/build.sh            # also runs ../libpcap/build.sh if needed
#   ./tcpdump/make-deb.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
TD_VERSION="${TD_VERSION:-4.99.5}"
PCAP_VERSION="${PCAP_VERSION:-1.10.5}"
SRC="${TD_SRC:-$HOME/ios-tool/tcpdump-src/tcpdump-$TD_VERSION}"
CC="$root/tools/cc-wrapper.sh"

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:?set IOS_LD64 to the cctools ld64}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

[ -f "$HOME/ios-tool/libpcap-src/libpcap-$PCAP_VERSION/libpcap.a" ] || \
    { echo "building libpcap first" >&2; bash "$root/libpcap/build.sh"; }

# ------------------------------------------------------------- source ----
[ -d "$SRC" ] || {
    mkdir -p "$HOME/ios-tool/tcpdump-src"
    curl -fL https://www.tcpdump.org/release/tcpdump-$TD_VERSION.tar.gz \
        -o /tmp/tcpdump.tar.gz
    tar -C "$HOME/ios-tool/tcpdump-src" -xzf /tmp/tcpdump.tar.gz
}

# tcpdump discovers its libpcap as ../libpcap-X.Y.Z (no --with-pcap option
# exists in 4.99.5; passing one is silently ignored with a WARNING)
ln -sfn "$HOME/ios-tool/libpcap-src/libpcap-$PCAP_VERSION" \
    "$HOME/ios-tool/tcpdump-src/libpcap-$PCAP_VERSION"

cd "$SRC"
[ -f ios-config.site ] || cp "$root/wget/ios-config.site" ios-config.site

make distclean >/dev/null 2>&1 || true
CC="$CC" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
    CONFIG_SITE="$SRC/ios-config.site" \
    ./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools \
        --without-smi --without-crypto --without-user >/dev/null

# Flat-namespace link probes always succeed: undefine the pcap APIs that
# genuinely do not exist in libpcap $PCAP_VERSION (see header comment).
for m in HAVE_PCAP_SET_OPTIMIZER_DEBUG HAVE_PCAP_SET_PARSER_DEBUG \
         HAVE_PCAP_FINDALLDEVS_EX HAVE_PCAP_OPEN; do
    sed -i "s|^#define $m 1$|/* #undef $m -- flat-namespace link probes always succeed; symbol is NOT in libpcap $PCAP_VERSION (verified against libpcap.a symbol table) */|" config.h
done

find . -name '*.o' -delete; rm -f tcpdump
make -j"$(nproc)" >/dev/null

ldid -S tcpdump
mkdir -p "$root/out"
cp tcpdump "$root/out/tcpdump-$TD_VERSION-armv7"
echo "==> $root/out/tcpdump-$TD_VERSION-armv7"
echo "    next: ./tcpdump/make-deb.sh"
