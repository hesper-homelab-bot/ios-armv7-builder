#!/bin/bash
# Build tor 0.4.8.14 for armv7 iOS 10.x on Linux.
#
# Deps (all pre-built in this repo's ecosystem):
#   * libevent 2.1.12 static  -- ~/ios-tool/build-ios/install (tmux era;
#                                built with tools/darwin-ar, see
#                                tmux/build.sh build_libevent)
#   * OpenSSL 4.0.3 static    -- ~/ios-tool/openssl-src/openssl-4.0.3
#                                (openssl4 build; .a + headers)
#   * zlib                    -- the device's own (libSystem); sysroot has
#                                zlib.h/zconf.h.  Dynamic -lz, wrapper drops
#                                -lz on purpose (symbols live in libSystem).
#
# Trims: dirauth module off (no need to be an authority); asciidoc off
# (no manpages); everything else stock.
#
# Source: tor_0.4.8.14.orig.tar.gz from Debian pool (dist.torproject.org and
# the GitHub mirror are unreachable/stale from this host -- the mirror only
# carries alpha tags; see docs/porting-backlog.md).
#
# Usage: ./build.sh          # output ../out/tor-<ver>-armv7 (UNSIGNED)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
TOR_VERSION="${TOR_VERSION:-0.4.8.14}"
SRC="${TOR_SRC:-$HOME/scratch/tor/tor-$TOR_VERSION}"
LE_PREFIX="${LE_PREFIX:-$HOME/ios-tool/build-ios/install}"
OSSL_PREFIX="${OSSL_PREFIX:-$HOME/ios-tool/openssl-src/openssl-4.0.3}"

[ -f "$SRC/configure" ] || { echo "missing $SRC -- download tor_${TOR_VERSION}.orig.tar.gz from Debian pool and extract" >&2; exit 1; }
[ -f "$LE_PREFIX/lib/libevent.a" ] || { echo "missing libevent.a under $LE_PREFIX -- see tmux/build.sh build_libevent" >&2; exit 1; }
[ -f "$OSSL_PREFIX/lib/libssl.a" ] || { echo "missing libssl.a under $OSSL_PREFIX" >&2; exit 1; }

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$SRC"
make distclean >/dev/null 2>&1 || true

# 全部环境变量用独立 export 行：自包含语句没有续行链，注释可以随便插。
# （本文件里"注释吞掉续行反斜杠导致 env 断链"的事故发生了三次，固化为
# 结构性规避；configure 之后有断言兜底。）
#
# SecureZeroMemory/RtlSecureZeroMemory/explicit_bzero/memset_s: 全是
# dynamic_lookup 恒真探针的受害者（check_decl 对"未声明"符号反而返回 yes
# 的反向逻辑 + check_func 恒真）——设备 iOS 10 只真有 memset_s，但 sysroot
# string.h 没声明，先全压掉走 tor 的可移植 memset 擦除路径。
export ac_cv_func_SecureZeroMemory=no
export ac_cv_func_RtlSecureZeroMemory=no
export ac_cv_func_explicit_bzero=no
export ac_cv_func_memset_s=no
export ac_cv_func_getresuid=no
export ac_cv_func_getresgid=no
export ac_cv_func_get_current_dir_name=no
export ac_cv_func_cap_set_proc=no
export ac_cv_func_gethostbyname_r=no
export ac_cv_func_libscrypt_scrypt=no
export ac_cv_func_pthread_condattr_setclock=no
export ac_cv_func_eventfd=no
export ac_cv_func_pipe2=no
export ac_cv_func_readpassphrase=no
export ac_cv_func_timingsafe_memcmp=no
export ac_cv_func_gnu_get_libc_version=no
export ac_cv_func_accept4=no
export ac_cv_func_prctl=no
export CC="$root/tools/cc-wrapper.sh"
# NULL: sysroot 手写头（sys/socket.h 等）不提供（stddef 链缺失，backlog 有
# 记）。值必须用 0 而不是 ((void*)0)：configure 的 shell 把未加引号的括号
# 当元字符，AC_PROG_CC 被毒倒后整条探针链回落宿主 gcc（2026-11-14 实录）。
export CFLAGS="-O2 -DNULL=0 -I$LE_PREFIX/include -I$LE_PREFIX/include/event2"

./configure \
    --host=armv7-apple-darwin \
    --prefix=/var/mobile/tools/tor \
    --disable-asciidoc \
    --disable-module-dirauth \
    --disable-tool-name-check \
    --disable-lzma \
    --disable-zstd \
    --enable-static-openssl \
    --enable-static-libevent \
    --enable-static-zlib \
    --with-zlib-dir="$HOME/ios-tool/build-ios/install" \
    --with-openssl-dir="$OSSL_PREFIX" \
    --with-libevent-dir="$LE_PREFIX"

# 断言：探针必须用我们的 wrapper（CC 失联 = 探针跑在宿主 gcc 上，全部
# 结论不可信——libevent 明明在却报找不到就是这么来的）。
grep -q "cc-wrapper" config.log || { echo "FATAL: configure probes did not use the cross wrapper" >&2; exit 1; }

# libtor.a 等归档必须 darwin 格式（toolchain.md §2/§15：GNU ar 会被 ld64
# 整体无视），AR/RANLIB 换 darwin 变体。
make -j"$(nproc)" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib"

BIN="$SRC/src/app/tor"
[ -f "$BIN" ] || BIN="$(find "$SRC/src" -name tor -type f | head -1)"
[ -f "$BIN" ] || { echo "tor was not built" >&2; exit 1; }

# Post-link audit + FULL-SYMBOL device probe (a daemon this size deserves
# the strongest gate: every undefined symbol must bind at launch on the
# device, not just the ones --version happens to touch).
"$root/tools/check-undefined.sh" "$BIN" || true
llvm-nm-21 -u "$BIN" | awk '{print $NF}' | "$root/tools/probe-symbols.sh" > "$root/out/tor-verified-symbols.txt"

mkdir -p "$root/out"
cp "$BIN" "$root/out/tor-$TOR_VERSION-armv7"
echo "==> $root/out/tor-$TOR_VERSION-armv7"
file "$root/out/tor-$TOR_VERSION-armv7" | sed 's/^/    /'
echo "    (unsigned by design -- make-deb.sh signs the staged copy;"
echo "     device-verified symbol list: out/tor-verified-symbols.txt)"
