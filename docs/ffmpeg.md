# FFmpeg 9.0.2 移植专项（armv7 iOS 10.3.3）

> 包：`ffmpeg_9.0.2-1_iphoneos-arm.deb`（19MB）
> 构建脚本注释即详细文档：`ffmpeg/build.sh`
> 本文记录**状态、立项依据、工具链特配、以及 SDK sysroot 模式的首次大工程落地**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 9.0.2 |
| 包名 | `ffmpeg_9.0.2-1_iphoneos-arm.deb`（19MB） |
| 产物 | `ffmpeg` + `ffprobe`（**全内置编解码器，静态**） |
| 安装路径 | `/var/mobile/tools/ffmpeg` |
| 定位 | backlog 里的**"远期最大工程"清仓**（用户 2026-11-15「ffmpeg开干吧」） |
| 详录 | `docs/toolchain.md` §18 |

## 2. 立项依据（先例 + 源码侦察）

**BigBoss 先例**：`com.nin9tyfour.ffmpeg` 2.6.1-1（2015 年，Depends 仅
`firmware>=4.0`，deb 9.4MB）——**证明自包含全编解码器在 armv7 iOS 可行**。

**源码侦察结论**（子 agent 侦察报告，一级源码逐行核实 release/9.0 的 configure）：

| 结论 | 细节 |
|---|---|
| armv7 **全分支仍受支持** | 5.1→9.0 的 `ARCH_LIST` 中 arm 逐分支=1，**无 32-bit ARM 移除公告** |
| **gas 检查失败 = configure 直接 die** | arm/aarch64 下报 `GNU assembler not found` → **`gas-preprocessor.pl` 必须在 PATH**。configure 对 darwin 自动探测并以它包装 `$cc`（configure 6599-6609） |
| 交叉编译**不会卡在运行测试** | `--enable-cross-compile` 后 `test_exec` **只链接不运行**（1693-1695） |
| 无内核版本下限检查 | `getrandom`/`memfd` 等老内核缺口**不构成 configure 依赖**（运行期自适应） |
| darwin 分支行为 | （6177 起）armv7 → **macho32**；给了 `--sysroot` 会自动补 `-isysroot` 给 cc/ld；`--enable-pic` 避开 `-mdynamic-no-pic` |

## 3. 工具链特配（本项目 cc-wrapper 语义）

| 项 | 做法 | 原因 |
|---|---|---|
| cc **与 ld 都走 cc-wrapper** | `--cc` 和 `--ld` 都设为 wrapper | **直连 clang 会调到宿主 `ld.bfd`**（历史教训） |
| ar/ranlib 用 darwin 变体 | `tools/darwin-ar` / `darwin-ranlib` | ld64 **拒收 GNU 归档格式**（`toolchain.md` §2） |
| nm/strip 用 LLVM 版 | `llvm-nm-21` / `llvm-strip-21` | GNU nm **不识 macho** |
| SDK sysroot 模式 | `IOS_SYSROOT=~/ios-tool/iPhoneOS10.3.sdk` | **AGENTS 规则 5，本仓库首个大工程落地** |
| **zlib 走 `--extra-libs` 传绝对路径 `.a`** ★ | 不能只靠 `-lz` | cc-wrapper 把 `-lz` 吞进"libSystem"（基于"zlib 在 libSystem"的**旧认知**；2026-11-14 探针证明 **iOS 10.3.3 的 libSystem 不含 zlib**）。而 `dynamic_lookup` 会让链接探针**恒真**（假阳性 → 设备上才炸）。绝对路径 `.a` 走 wrapper 的 `*.a` 分支直链，**真链接真解析** |
| **`libios-compat.a` 必须显式追加** ★ | 手动加进链接行 | cc-wrapper 尾部的 COMPAT 自动追加是**按 musl sysroot 相对定位**的（`$SYSROOT/../..`），**SDK 模式下路径断裂且静默缺失**。而 libssl/libcrypto 会拖出 `recvmmsg`/`sendmmsg` 桩依赖 |

## 4. 明确**不加**的两个选项

| 选项 | 为什么不加 |
|---|---|
| `--disable-asm` | 会把 arch **整体降为 c**，**全 DSP SIMD 消失**，A6X 解码性能崩溃（侦察 8258 行核实） |
| `--enable-small` | 牺牲速度 |

> 与 `docs/openssl.md` 同样的取舍思路：**能上汇编就上汇编**。

## 5. 源码与依赖

```
Source:          https://www.ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz
gas-preprocessor: https://github.com/FFmpeg/gas-preprocessor  （必须在 PATH）
OpenSSL 4.0.3:   静态库（见 docs/openssl.md）
zlib 1.3.1:      静态库
```

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `ffmpeg/build.sh` | 构建（侦察结论与全部特配在注释里） |
| `ffmpeg/make-deb.sh` | 打包 |
| `docs/toolchain.md` §18 | ffmpeg 的构建雷区与验收全录 |
| `docs/toolchain.md` §16 | SDK sysroot 模式的由来与金丝雀记录 |
