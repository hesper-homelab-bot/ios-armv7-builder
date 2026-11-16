# class-dump 3.5.2 移植专项（armv7 iOS 10.3.3）

> 包：`class-dump4_3.5.2-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`class-dump/build.sh`
> 本文记录**真实 SDK 破局、Apple 头世界的隔离策略、以及 MRC 的 `__weak` 词法陷阱**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 3.5.2（**nygard fork，commit `2c82b4f`**） |
| 包名 | `class-dump4_3.5.2-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools/class-dump/class-dump`（`bin/` 下有软链） |
| 验收 | ✅ 宿主编一个 ObjC 测试程序（`CDPTestWidget`）部署后，**class-dump 现场解剖出类 / ivar / 属性 / 方法全表** |

## 2. 破局：真实 SDK（用户拍板的方向）

**一直以来的卡点就是头文件**：76 个 ObjC 源文件通过 prefix header
import `<Foundation/Foundation.h>`，而**设备没有 SDK 头，我们基于 musl 的
sysroot 也没有**。

**解决方案**（用户 2026-11-14 拍板）：用 `github.com/xybp888/iOS-SDKs` 的
**真实 iPhoneOS10.3.sdk** —— **与设备精确同版本**。

> 这一条同时兑现了 backlog 里"用户指出的 xybp888/iOS-SDKs 破局"。

## 3. ★ 头世界隔离策略（关键设计）

**把 class-dump 整个编译在 Apple 头世界里**：

| 标志 | 作用 |
|---|---|
| `-isystem $SDK/usr/include` | **Apple C 头遮蔽 musl 的**（对这个二进制而言）；于是类型/原型与设备的 libSystem **精确匹配** |
| `-F $SDK/System/Library/Frameworks` | Foundation/CoreFoundation 的 umbrella + SDK **官方 `.tbd` 桩**；ld64 链接时用它，审计门禁把它列入白名单 |

> **musl sysroot 仅作为 `-isysroot` 兜底**，用于 SDK 确实没有的东西。
>
> ⚠️ **绝对不要混用**：这个二进制里的一切都编译在 Apple 头世界下。

## 4. 审计白名单的权威底本

SDK 的官方 tbd 被拷进审计白名单目录（门禁 glob 读 `$HOME/ios-tool/*.tbd`）：

- 框架 tbd（`Foundation` / `CoreFoundation` / `libobjc`）**按名拷贝**
- **`usr/lib` 全量官方 tbd**：CommonCrypto / Blocks / libSystem 的**全符号表**
  —— 这是 **iOS 10.3 的官方设备符号宇宙**，白名单从此有了**权威底本**

> ⚠️ **`libSystem.tbd` 是 re-export 壳**，真符号在 `usr/lib/system/`
> 的子库 tbd 里 —— **两层都要拷**。
>
> 手写的 `libSystem.tbd` **不动**（拷成 `sdk-libSystem.tbd` 并入白名单）。

## 5. 坑

### 5.1 ★ MRC 的 `__weak` / `weak` 属性：**宏无效，必须字面量 sed**

clang 在**词法层**直接识别 `__weak`。这意味着：

- **定义宏没用** —— 必须在源码里**字面量 `sed`**
- **弱引用大多住在 `.h` 里** —— **只扫 `.m` 文件会漏**

### 5.2 `mach-o/loader.h` 早于 `LC_BUILD_VERSION`

10.3 SDK 的 `mach-o/loader.h` **早于 2016 年引入的 `LC_BUILD_VERSION`**，
平台/工具常量与结构体**整块缺失**，而 `CDLCBuildVersion.m` 要用。

**修法**：注入幂等 shim（`-include obj/cd-platform-shim.h`），
值取 **cctools 官方表**，包含：

- `LC_NOTE`（0x33）、`LC_BUILD_VERSION`（0x32）+ `struct build_version_command`
  / `struct build_tool_version`
- 全 `PLATFORM_*` 常量（`PLATFORM_IOS`=2…）
- 全 `TOOL_*` 常量
- `PAGE_SIZE`（armv7/iOS 为 `0x1000`；arm64 才是 `0x4000`）

> `TVOSSIMULATOR(8)` / `WATCHOSSIMULATOR(9)` / `TUNES(10)` 为**尽力而为**
> （仅影响打印标签）。

### 5.3 NeXT 时代 `libc.h` 摘除

（同批处理的兼容性问题。）

### 5.4 cc-wrapper 的 `-F` 通道

SDK 头世界需要 `-F` 指向框架目录 —— **cc-wrapper 为此补了 `-F` 双投递**
（见 `docs/toolchain.md` 的工具链修复记录）。

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `class-dump/build.sh` | 构建（头世界策略 + platform shim 全文） |
| `class-dump/make-deb.sh` | 打包（p7zip 模式：真二进制 + bin 软链） |
| `$HOME/ios-tool/*.tbd` | 审计白名单（SDK 官方 tbd） |
| `docs/toolchain.md` §16 | SDK sysroot 模式的由来 |
