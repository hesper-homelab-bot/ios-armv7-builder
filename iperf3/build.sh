#!/bin/bash
# Build iperf3 3.22.1 for armv7 iOS 10.x.  SDK sysroot mode.
#
# Walls (see docs/iperf3.md):
#   - configure 恒真探针压清单: cpuset_setaffinity/sched_setaffinity/
#     SetProcessAffinityMask/clock_nanosleep 全部 ac_cv_*=no(iOS 10 无此 API,
#     dynamic_lookup 恒真探针会放它们进 config.h 然后编译/运行期死)。
#   - libtool 的 GNU ar 归档 ld64 静默无视(§2),libtool 内嵌 AR 不吃
#     make 覆盖 → **绕开归档,configure+make 只出 .o,最后手链**。
#   - 手链 = 全部 .o 一次喂 cc-wrapper(138/138 符号全解析)。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:-${LD64:-$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld}}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
CC="$root/tools/cc-wrapper.sh"
mkdir -p "$OUT"

SRC="$here/src"
[ -d "$SRC" ] || { echo "missing $SRC (source tree; keep iperf-3.22.1 extracted there)" >&2; exit 1; }

cd "$SRC"
if [ ! -f Makefile ]; then
  ac_cv_func_cpuset_setaffinity=no ac_cv_func_sched_setaffinity=no \
  ac_cv_func_SetProcessAffinityMask=no ac_cv_func_clock_nanosleep=no \
  CC="$CC" ./configure --host=armv7-apple-ios --prefix=/var/mobile/tools/iperf3 \
    --disable-shared --without-openssl
fi
make -j4 >/dev/null 2>&1 || true   # .o 们出来即可;归档/链接交给手链

"$CC" -O2 -o "$OUT/iperf34-armv7" \
  src/cjson.o src/dscp.o src/iperf_api.o src/iperf_auth.o \
  src/iperf_client_api.o src/iperf_error.o src/iperf_locale.o \
  src/iperf_pthread.o src/iperf_server_api.o src/iperf_tcp.o \
  src/iperf_time.o src/iperf_udp.o src/iperf_util.o src/net.o \
  src/tcp_info.o src/timer.o src/units.o src/iperf3-main.o
ldid -S "$OUT/iperf34-armv7" 2>/dev/null || true
echo "==> $OUT/iperf34-armv7"
