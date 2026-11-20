#!/bin/bash
# Build ifconfig + route (Apple network_cmds-457, Darwin 16 era) for
# armv7 iOS 10.x.  SDK sysroot mode per the 2026-11-15 ruling (§16).
#
# Why 457: iOS 10.3.3 = Darwin 16 = xnu-3789, same era as macOS 10.12
# (network_cmds-457).  Later tags drift to newer kernels/SDK idioms.
#
# Why -DPRIVATE and port-local include/ (see docs/ifconfig.md):
#   - kldload/modstat (sys/module.h, sys/linker.h) are FreeBSD leftovers,
#     already inside #ifndef __APPLE__ upstream -- no patch needed.
#   - The iOS 10.3 SDK ships PUBLIC cuts of net/if.h, sys/sockio.h and
#     net/if_var.h; network_cmds needs the PRIVATE sections (if_descreq,
#     ifr_log/ifru_2kcl, SIOCSIFDESC/LINKPARAMS/THROTTLE/LOG/2KCL,
#     if_bandwidths/if_latencies/if_interface_state, if_traffic_class/...).
#     Fix: xnu-3789.70.16 kernel headers in include/ (stamped, some with
#     extern-"C" wraps around kernel-private decls per the fetch-tool gate)
#     + -DPRIVATE, exactly how Apple builds these tools internally.
#   - include/ = 18 SDK-missing xnu headers + 3 shadowing copies of
#     net/if.h, net/if_var.h, sys/sockio.h.  No patch on the .c files.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"

# Canonical build env (docs/toolchain.md §1); allow overrides.
export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"   # hand-written stubs anchor -lSystem
export IOS_LD64="${IOS_LD64:-${LD64:-$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld}}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

CC="$root/tools/cc-wrapper.sh"
mkdir -p "$OUT"

IFC="$here/ifconfig.tproj"
SRC_IFC="$IFC/ifconfig.c $IFC/af_inet.c $IFC/af_inet6.c $IFC/af_link.c \
$IFC/ifclone.c $IFC/ifmedia.c $IFC/ifbond.c $IFC/ifbridge.c $IFC/ifvlan.c"

"$CC" -O2 -Wall -DPRIVATE -I"$here/include" -o "$OUT/ifconfig-armv7" $SRC_IFC
ldid -S "$OUT/ifconfig-armv7" 2>/dev/null || true
echo "==> $OUT/ifconfig-armv7"

"$CC" -O2 -Wall -DPRIVATE -I"$here/include" -o "$OUT/route-armv7" "$here/route.tproj/route.c"
ldid -S "$OUT/route-armv7" 2>/dev/null || true
echo "==> $OUT/route-armv7"
