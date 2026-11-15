#!/bin/bash
# Build FFmpeg 9.0.2 for armv7 iOS 10.3.3 (iPad4/A6X).
#
# 立项（用户 2026-11-15 "ffmpeg开干吧"）：backlog 远期最大工程。
# BigBoss 先例 com.nin9tyfour.ffmpeg 2.6.1-1（2015，Depends 仅
# firmware>=4.0，deb 9.4MB）证明自包含全编解码器在 armv7 iOS 可行。
#
# 情报（子 agent 侦察报告 2026-11-15，一级源码逐行核实 release/9.0 configure）：
#   * armv7 在 5.1→9.0 全分支仍受支持（ARCH_LIST 的 arm 逐分支=1，
#     无 32-bit ARM 移除公告）
#   * arm/aarch64 下 gas 检查失败 = configure 直接 die
#     （"GNU assembler not found"）——gas-preprocessor.pl 必须在 PATH，
#     configure 对 darwin 自动探测并以它包装 $cc（configure 6599-6609）
#   * --enable-cross-compile 后 test_exec 只链接不运行（1693-1695），
#     交叉编译不会卡在运行测试
#   * 无内核版本下限检查；getrandom/memfd 等老内核缺口不构成 configure
#     依赖（运行期自适应）
#   * darwin 分支（6177 起）：armv7 → macho32；给了 --sysroot 自动补
#     -isysroot 给 cc/ld（wrapper 会吞掉 -isysroot/-arch/-target，无害）；
#     --enable-pic 避开 -mdynamic-no-pic
#
# 工具链特配（本项目 cc-wrapper 语义）：
#   * cc 与 ld 都走 cc-wrapper（直连 clang 会调到宿主 ld.bfd——历史教训）
#   * ar/ranlib 用 darwin 变体（ld64 拒 GNU 归档格式）
#   * nm/strip 用 llvm-nm-21/llvm-strip-21（GNU nm 不识 macho）
#   * SDK sysroot 模式（AGENTS 规则 5，本仓库首个大工程落地）
#   * zlib 静态库走 --extra-libs 传绝对路径 .a——不能只靠 -lz：
#     cc-wrapper 把 -lz 吞进 libSystem（基于"zlib 在 libSystem"的旧认知，
#     2026-11-14 探针证明 iOS 10.3.3 的 libSystem 不含 zlib），而
#     dynamic_lookup 会把链接探针变成恒真（假阳性→设备上才炸）。
#     绝对路径 .a 走 wrapper 的 *.a 分支直链，真链接真解析。
#   * libios-compat.a 必须显式追加：cc-wrapper 尾部的 COMPAT 自动追加
#     按 musl sysroot 相对定位（$SYSROOT/../..），SDK 模式下路径断裂
#     且静默缺失；libssl/libcrypto 拖 recvmmsg/sendmmsg 桩依赖它。
#
# 不加的东西：--disable-asm（会把 arch 整体降为 c、全 DSP SIMD 消失，
# A6X 解码性能崩——侦察 8258 行核实）；--enable-small（牺牲速度）。
#
# Source: https://www.ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz
# gas-preprocessor: https://github.com/FFmpeg/gas-preprocessor
#
# Usage: IOS_LD64=... ./build.sh    # out-of-tree build in obj/
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
FFSRC="${FFMPEG_SRC:-$HOME/scratch/ffmpeg/src9}"
SDK="${IOS_SDK:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
OSSL="${OSSL_PREFIX:-$HOME/ios-tool/openssl-src/openssl-4.0.3}"
ZLIB_STATIC="${ZLIB_STATIC:-$HOME/ios-tool/build-ios/install/lib/libz.a}"
COMPAT_STATIC="$root/sysroot-overlay/usr/lib/libios-compat.a"
GASPP="$HOME/ios-tool/gas-preprocessor"

[ -f "$FFSRC/configure" ] || {
	echo "missing $FFSRC/configure -- download ffmpeg-9.0.2.tar.xz from" >&2
	echo "  https://www.ffmpeg.org/releases/ and extract to src9/" >&2
	exit 1
}
[ -f "$SDK/usr/include/uuid/uuid.h" ] || { echo "missing SDK under $SDK" >&2; exit 1; }
[ -f "$OSSL/lib/libssl.a" ] || { echo "missing $OSSL/lib/libssl.a" >&2; exit 1; }
[ -f "$ZLIB_STATIC" ] || { echo "missing $ZLIB_STATIC" >&2; exit 1; }
[ -f "$COMPAT_STATIC" ] || { echo "missing $COMPAT_STATIC" >&2; exit 1; }
[ -f "$GASPP/gas-preprocessor.pl" ] || {
	echo "missing gas-preprocessor.pl -- git clone --depth 1" >&2
	echo "  https://github.com/FFmpeg/gas-preprocessor $GASPP" >&2
	exit 1
}
command -v llvm-nm-21 >/dev/null || { echo "missing llvm-nm-21" >&2; exit 1; }

export IOS_SYSROOT="${IOS_SYSROOT:-$SDK}"
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set IOS_LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

CC="$root/tools/cc-wrapper.sh"
AR="$root/tools/darwin-ar"
RANLIB="$root/tools/darwin-ranlib"

build="$here/obj"
rm -rf "$build"
mkdir -p "$build" "$root/out"
cd "$build"

# gas-preprocessor.pl 在 PATH → configure darwin 分支自动采用
PATH="$GASPP:$PATH" \
"$FFSRC/configure" \
	--enable-cross-compile \
	--target-os=darwin \
	--arch=arm \
	--cpu=armv7-a \
	--enable-pic \
	--cc="$CC" \
	--ld="$CC" \
	--ar="$AR" \
	--ranlib="$RANLIB" \
	--nm=llvm-nm-21 \
	--strip=llvm-strip-21 \
	--sysroot="$SDK" \
	--extra-cflags="-I$OSSL/include" \
	--extra-ldflags="-L$OSSL/lib -F$SDK/System/Library/Frameworks" \
	--extra-libs="$ZLIB_STATIC $COMPAT_STATIC" \
	--enable-zlib \
	--enable-openssl \
	--disable-autodetect \
	--disable-doc \
	--disable-avdevice \
	--disable-debug \
	--disable-iconv \
	--disable-bzlib \
	--disable-lzma \
	--disable-ffplay \
	--prefix=/var/mobile/tools/ffmpeg

# ---- configure 后压制：dynamic_lookup 恒真探针误开的 HAVE_* ----
# ffmpeg 的 SYSTEM_FUNCS 探测（check_func）在本工具链下链接恒真：
# 任何符号都"存在"（-undefined dynamic_lookup），Windows/BSD/Linux
# 专属函数因此误进 config.h（HAVE_CLOSESOCKET=1 → closesocket 宏不
# 生效 → network.c 编译失败是第一例，2026-11-15）。--disable-XXX
# 不达 SYSTEM_FUNCS（只在 CONFIG/HAVE_LIST 作用域），只能 configure
# 后直接修 config.h。ffmpeg 的 config.h 仅 configure 时生成、make 不
# 重写，修正不会丢（对照 toolchain.md §10 的重生成陷阱）。
for sym in \
	CLOSESOCKET ALIGNED_MALLOC COMMANDLINETOARGVW GETMODULEHANDLE \
	GETPROCESSAFFINITYMASK GETPROCESSMEMORYINFO GETPROCESSTIMES \
	GETSTDHANDLE GETSYSTEMTIMEASFILETIME KBHIT MAPVIEWOFFILE \
	PEEKNAMEDPIPE SETCONSOLETEXTATTRIBUTE SETCONSOLECTRLHANDLER \
	SETDLLDIRECTORY GETHRTIME ELF_AUX_INFO PTHREAD_SET_NAME_NP \
	PTHREAD_SETAFFINITY_NP SCHED_GETAFFINITY
do
	sed -i "s/^#define HAVE_${sym} 1\$/#define HAVE_${sym} 0/" config.h
done
grep -q "^#define HAVE_CLOSESOCKET 0" config.h || {
	echo "FATAL: HAVE_CLOSESOCKET not suppressed -- sed missed" >&2
	exit 1
}
echo "config.h suppression OK"

echo "configure OK"
make -j"$(nproc)"

echo "== built =="
ls -l "$build/ffmpeg" "$build/ffprobe"
