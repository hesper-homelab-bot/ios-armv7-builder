#!/bin/bash
# Build class-dump (nygard fork, commit 2c82b4f) for armv7 iOS 10.3.3.
#
# The blocker was always headers: 76 ObjC sources import
# <Foundation/Foundation.h> via the prefix header, and neither the device
# nor our musl-based sysroot ships SDK headers.  Solution (用户 2026-11-14
# 拍板): the REAL iPhoneOS10.3.sdk from github.com/xybp888/iOS-SDKs --
# exact same version as the device.
#
# Header world strategy: compile class-dump in the APPLE header world --
#   -isystem $SDK/usr/include  (Apple C headers shadow musl's for this
#                               binary; types/prototypes then match the
#                               device's libSystem exactly)
#   -F $SDK/System/Library/Frameworks  (Foundation/CoreFoundation umbrellas
#                               + the SDK's official .tbd stubs, which ld64
#                               uses at link and the audit gate whitelists)
# The musl sysroot stays as -isysroot fallback for anything the SDK lacks.
# Do NOT mix: everything in this binary compiles against Apple headers.
#
# Source: git clone --depth 1 https://github.com/nygard/class-dump.git
#         (commit 2c82b4f).  SDK: iPhoneOS10.3.sdk.zip from the iOS-SDKs
#         release (iOS-SDKs tag).
#
# Usage: ./build.sh          # output ../out/class-dump-<ver>-armv7 (UNSIGNED)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
CD_SRC="${CLASS_DUMP_SRC:-$HOME/scratch/class-dump/class-dump-src}"
SDK="${IOS_SDK:-$HOME/scratch/iPhoneOS10.3.sdk}"
SDK_FW="$SDK/System/Library/Frameworks"

[ -f "$CD_SRC/class-dump.m" ] || {
    echo "missing $CD_SRC -- git clone --depth 1 https://github.com/nygard/class-dump.git" >&2
    echo "  sources.lock row 'class-dump' pins a master commit tarball instead" >&2
    echo "  (upstream has no releases) -- verify/fetch with:" >&2
    echo "    $root/tools/fetch-src.sh --lock class-dump" >&2
    exit 1
}
[ -f "$SDK_FW/Foundation.framework/Headers/Foundation.h" ] || { echo "missing SDK Foundation headers under $SDK -- download iPhoneOS10.3.sdk.zip (xybp888/iOS-SDKs iOS-SDKs release)" >&2; exit 1; }

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# SDK 官方 tbd 拷入审计白名单目录（门禁 glob 读 $HOME/ios-tool/*.tbd；
# 不动手写的 libSystem.tbd——拷成 sdk-libSystem.tbd 并入白名单）。
# 框架 tbd（Foundation/CoreFoundation/libobjc）按名拷贝。
for t in Foundation CoreFoundation libobjc; do
    src="$(find "$SDK" -name "$t.tbd" | head -1)"
    [ -n "$src" ] || { echo "SDK tbd not found: $t" >&2; exit 1; }
    [ -f "$HOME/ios-tool/$t.tbd" ] || cp "$src" "$HOME/ios-tool/$t.tbd"
done
# usr/lib 全量官方 tbd（CommonCrypto/Blocks/libSystem 全符号表——iOS 10.3
# 的官方设备符号宇宙，白名单从此有了权威底本）。注意 libSystem.tbd 是
# re-export 壳，真符号在 usr/lib/system/ 子库 tbd 里——两层都要拷。
for t in "$SDK"/usr/lib/*.tbd "$SDK"/usr/lib/system/*.tbd; do
    [ -f "$t" ] || continue
    dst="$HOME/ios-tool/sdk-$(basename "$t")"
    [ -f "$dst" ] || cp "$t" "$dst"
done

CD_VERSION="$(grep -m1 -A1 CFBundleShortVersionString "$CD_SRC/Info.plist" 2>/dev/null | tail -1 | tr -d ' </>string' || true)"
CD_VERSION="${CD_VERSION:-3.5.2}"

cd "$CD_SRC"
mkdir -p obj

CC="$root/tools/cc-wrapper.sh"
mkdir -p obj
# 10.3 SDK 的 mach-o/loader.h 早于 LC_BUILD_VERSION 平台常量（cctools 官方
# 值表）；CDLCBuildVersion.m 要用 —— 注入幂等 shim（-include）。
cat > obj/cd-platform-shim.h <<'EOF'
#ifndef CD_PLATFORM_SHIM_H
#define CD_PLATFORM_SHIM_H
#include <stdint.h>
/* 10.3 SDK 的 mach-o/loader.h 早于 LC_BUILD_VERSION（2016 引入）——平台/
 * 工具常量与结构体整块缺失。值取 cctools 官方表；TVOSSIMULATOR(8)/
 * WATCHOSSIMULATOR(9)/TUNES(10) 为尽力而为（仅影响打印标签）。 */
#ifndef LC_NOTE
#define LC_NOTE 0x33
#endif
#ifndef LC_BUILD_VERSION
#define LC_BUILD_VERSION 0x32
struct build_version_command {
	uint32_t cmd;
	uint32_t cmdsize;
	uint32_t platform;
	uint32_t minos;
	uint32_t sdk;
	uint32_t ntools;
};
struct build_tool_version {
	uint32_t tool;
	uint32_t version;
};
#endif
#ifndef PLATFORM_MACOS
#define PLATFORM_MACOS 1
#define PLATFORM_IOS 2
#define PLATFORM_TVOS 3
#define PLATFORM_WATCHOS 4
#define PLATFORM_BRIDGEOS 5
#define PLATFORM_MACCATALYST 6
#define PLATFORM_IOSSIMULATOR 7
#define PLATFORM_TVOSSIMULATOR 8
#define PLATFORM_WATCHOSSIMULATOR 9
#define PLATFORM_TUNES 10
#define PLATFORM_IOSMAC 6
#endif
#ifndef TOOL_CLANG
#define TOOL_CLANG 1
#define TOOL_SWIFT 2
#define TOOL_LD 3
#endif
/* armv7/iOS 页大小 0x1000（arm64 为 0x4000——本目标用不到） */
#ifndef PAGE_SIZE
#define PAGE_SIZE 0x1000
#endif
#endif
EOF
PCH_FLAGS="-include $CD_SRC/MachObjC-Prefix.pch -include obj/cd-platform-shim.h"
INC_FLAGS="-I$CD_SRC/Source -I$CD_SRC/ThirdParty -isystem $SDK/usr/include -F$SDK_FW"

# __weak 在 MRC 下被现代 clang 当关键字在词法层直认（pch 里作者自己的
# 宏定义都绕不过，-D 也一样）——字面量替换为 __unsafe_unretained（幂等；
# class-dump 是跑完即退的批处理工具，弱引用零化语义不承载生命周期正确性）。
# 注意：弱引用/弱属性大多住在头文件（CDSection.h 等）——sed 必须覆盖
# Source/*.m **和** Source/*.h，只扫 .m 会漏（2026-11-14 踩过）。
sed -i 's/\b__weak\b/__unsafe_unretained/g' Source/*.m Source/*.h class-dump.m
# weak 属性在 MRC 下不可合成——降级为普通属性（幂等；含 nonatomic 变体）。
sed -i 's/@property (weak, /@property (/g; s/(nonatomic, weak, /(nonatomic, /g' Source/*.m Source/*.h class-dump.m

# class-dump.m 的 <libc.h> 是 NeXT 时代头（iOS SDK 没有）；它承载的符号
# （environ 等）unistd.h 已声明，直接摘除（幂等，tmux fixups 同款思路）。
sed -i '/#include <libc.h>/d' class-dump.m

# 1. 76 个 ObjC 源 + 入口 + ThirdParty/blowfish.c
for src in class-dump.m Source/*.m ThirdParty/*.c; do
    obj="obj/$(basename "${src%.*}").o"
    [ "$src" -nt "$obj" ] || continue
    "$CC" $PCH_FLAGS $INC_FLAGS -O2 -c "$src" -o "$obj"
done

# 2. link（-F 让 ld64 找 SDK 的官方 tbd；-L/usr/lib 兜底 -lobjc 自动链接）
"$CC" $INC_FLAGS -o class-dump obj/*.o \
    -F$SDK_FW -L$SDK/usr/lib \
    -framework Foundation -framework CoreFoundation

BIN="$CD_SRC/class-dump"
[ -f "$BIN" ] || { echo "class-dump was not built" >&2; exit 1; }

# 3. post-link audit（SDK tbd 已入白名单目录）
# ObjC 类/元类引用（_OBJC_CLASS_$_* 等）由 Objective-C 运行时在加载时从
# 共享缓存绑定——设计上就不进任何 tbd 符号表（官方 Foundation.tbd 也不
# 列它们），链接器只负责把 Foundation 框架拉进来。此模式限定这三类前缀。
ALLOWED_UNDEFINED='^_OBJC_(CLASS|METACLASS|EHTYPE)_\$' \
    "$root/tools/check-undefined.sh" "$BIN"

mkdir -p "$root/out"
cp "$BIN" "$root/out/class-dump-$CD_VERSION-armv7"
echo "==> $root/out/class-dump-$CD_VERSION-armv7"
file "$root/out/class-dump-$CD_VERSION-armv7" | sed 's/^/    /'
echo "    (unsigned by design -- make-deb.sh signs the staged copy;"
echo "     headers: real iPhoneOS10.3.sdk per docs/porting-backlog.md)"
