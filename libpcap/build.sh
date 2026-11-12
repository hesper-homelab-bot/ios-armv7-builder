#!/bin/bash
# Build libpcap 1.10.5 for armv7 iOS 10.x on Linux.
#
# The device has real /dev/bpf* devices (verified: /dev/bpf0-2, root can
# read them), but Apple does not ship <net/bpf.h> in any userland SDK.
# Two sysroot additions make the BPF support build (see ../tcpdump/build.sh
# for the consumer of all this):
#
#   * net/bpf.h      -- taken from xnu-3789.70.16 (the iOS 10.3 kernel
#                       release) via the gh api; it only needs two stub
#                       headers: sys/appleapiopts.h (empty shim) and
#                       sys/_types/_timeval32.h (two int32 fields on
#                       armv7 -- BPF_TIMEVAL is used in BIOCGRTIMEOUT).
#   * sys/param.h    -- appended with the BSD IN_CLASS* macros (pure
#                       address arithmetic, no kernel ABI).
#
# Walls found on the way (all recorded here so re-builds are boring):
#
#   * configure hardcodes `-arch x86_64 -arch arm64` into FULL_CFLAGS for
#     darwin hosts.  The cc-wrapper drops `-arch` tokens but not their
#     values, so the bare "x86_64"/"arm64" words reach clang as input
#     files.  Fix: strip the pair out of the generated Makefile.
#   * tcpdump finds a *local* libpcap build tree only if it sits next to
#     its own source dir (../libpcap-X.Y.Z) -- see tcpdump/build.sh, which
#     is why this script does NOT install libpcap anywhere for that purpose
#     (the install tree exists only because earlier attempts tried
#     --with-pcap, which tcpdump 4.99.5 does not even have).
#
# Usage:
#   export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot \
#          IOS_STUBDIR=$HOME/ios-tool \
#          IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
#          LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
#   ./libpcap/build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
PCAP_VERSION="${PCAP_VERSION:-1.10.5}"
SRC="${PCAP_SRC:-$HOME/ios-tool/libpcap-src/libpcap-$PCAP_VERSION}"
CC="$root/tools/cc-wrapper.sh"

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:?set IOS_LD64 to the cctools ld64}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ------------------------------------------------------------- source ----
[ -d "$SRC" ] || {
    mkdir -p "$HOME/ios-tool/libpcap-src"
    curl -fL https://www.tcpdump.org/release/libpcap-$PCAP_VERSION.tar.gz \
        -o /tmp/libpcap.tar.gz
    tar -C "$HOME/ios-tool/libpcap-src" -xzf /tmp/libpcap.tar.gz
}

# -------------------------------------------------- sysroot net/bpf.h ----
SYSINC="$root/tmp/sysroot/usr/include"
if [ ! -f "$SYSINC/net/bpf.h" ]; then
    mkdir -p "$SYSINC/net" "$SYSINC/sys/_types"
    gh api repos/apple-oss-distributions/xnu/contents/bsd/net/bpf.h?ref=xnu-3789.70.16 \
        --jq .content | base64 -d > "$SYSINC/net/bpf.h"
    printf '/* userland stub: Apple compatibility macro shim */\n#ifndef _SYS_APPEAR_APIOPTS_H\n#define _SYS_APPEAR_APIOPTS_H\n#endif\n' \
        > "$SYSINC/sys/appleapiopts.h"
    cat > "$SYSINC/sys/_types/_timeval32.h" <<'EOF'
/* userland stub: Darwin's 32-bit timeval (two int32 fields on armv7). */
#ifndef _SYS__TYPES__TIMEVAL32_H_
#define _SYS__TYPES__TIMEVAL32_H_
struct timeval32 {
	__int32_t	tv_sec;
	__int32_t	tv_usec;
};
#endif
EOF
fi

# ------------------------------------------------------- configure ----
cd "$SRC"
[ -f ios-config.site ] || cp "$root/wget/ios-config.site" ios-config.site
grep -q 'ac_cv_header_net_bpf_h' ios-config.site || cat >> ios-config.site <<'EOF'

# --- libpcap specific corrections (cross-compile probes all lie) ---
ac_cv_header_net_bpf_h=yes
ac_cv_linux_vers=none
EOF

make distclean >/dev/null 2>&1 || true
CC="$CC" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
    CONFIG_SITE="$SRC/ios-config.site" \
    ./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools \
        --disable-shared --disable-dbus --disable-rdma --without-libnl \
        >/dev/null

# strip the macOS fat-binary flags (see header comment)
sed -i 's/ -arch x86_64 -arch arm64//g' Makefile

make -j"$(nproc)" >/dev/null

# GNU thin archives are silently ignored by ld64 (docs/toolchain.md §2)
llvm-ar-21 --format=darwin rcs libpcap.a.new *.o
n=$(llvm-ar-21 t libpcap.a.new | wc -l)
[ "$n" -gt 0 ] || { echo "libpcap.a conversion produced 0 members" >&2; exit 1; }
mv libpcap.a.new libpcap.a

echo "==> $SRC/libpcap.a ($n members)"
echo "    tcpdump/build.sh picks it up automatically (../libpcap-$PCAP_VERSION)"
