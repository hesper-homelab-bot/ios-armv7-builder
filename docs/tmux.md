# tmux 3.8 移植专项（armv7 iOS 10.3.3）

> 包：`tmux_3.8-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`tmux/build.sh`
> **历史地位**：tmux 是本仓库**第一个移植的软件**。当时的取舍与今天不同
> ——见 §2。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 3.8（另有 3.5a 的早期构建） |
| 包名 | `tmux_3.8-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools` |
| 产物 | Mach-O armv7 可执行文件（`LC_VERSION_MIN_IPHONEOS 10.3`），链接设备自己的 libSystem 与 libncursesw |
| **构建模式** | **musl sysroot 模式**（**不是**今天的 SDK 模式） |

## 2. ★ 历史背景：为什么基建长在 tmux 身上

**tmux 是第一个移植的软件**，那会儿工具链**还不存在**——
所以 `tmux/build.sh` 顺带把当时需要的**一切**都自己做了：

| 职责 | 函数 | 产物 |
|---|---|---|
| 组装 sysroot | `make_sysroot` | `tmp/sysroot`（musl 头 + Darwin ABI overlay） |
| 构建 libevent | `build_libevent` | `$PREFIX/lib/libevent*.a`（tor 也用它） |
| 生成 `libSystem.tbd` 桩 | `generate_stub_and_relink` | `$IOS_STUBDIR/libSystem.tbd` |

**这些不是"tmux 应有的职责"，而是"第一个吃螃蟹的人被迫先造工具"。**
后来移植的包直接复用产物，于是形成了"很多 build.sh 第一句检查
`run tmux/build.sh first`"的现状。

### ⚠️ 今天该怎么做

**这些基建知识现已沉淀到 `docs/toolchain.md`**，而且
**新移植默认走 SDK sysroot 模式**（仓库 AGENTS.md 工作规则 5）：

```
旧（tmux 时代）：musl sysroot + 手工 Darwin overlay
新（2026-11-15 起）：IOS_SYSROOT=~/ios-tool/iPhoneOS10.3.sdk
                    （真 Apple SDK 头 + 手写 stub tbd）
```

**不是所有包都需要再跑一遍 `tmux/build.sh`** —— 那是历史遗留的
引导顺序，不是设计意图。查 `docs/toolchain.md` §16 确认当前做法。

**存量包不重编**（保留可复现性），所以 tmux 及其同代包仍在用
musl sysroot 产物。

## 3. sysroot 组装（`make_sysroot`）

```
musl 头（include/ + arch/generic/ + arch/<arch>/）
    + 生成的 bits/（mkalltypes.sed → alltypes.h、syscall.h）
        ↓ 被覆盖
sysroot-overlay/usr/include/   ← "我们为 Darwin ABI 修正过的一切"获胜
```

**最后一步是关键**：overlay **无条件覆盖**上面的 musl 头——
所有为 Darwin ABI 做的修正都在 `sysroot-overlay/` 里，
它是**唯一的真相来源**。

（该目录的成体系修复见 `docs/nmap.md` §4。）

## 4. ★ `libSystem.tbd` 桩的生成原理（**工具链的核心机制**）

> 虽然这段代码住在 tmux 里（§2 的历史成因），但它**不是 tmux 专属的**——
> 它是**整个链接模型的关键一环**，值得单独理解。

**问题**：**第一次链接总是"成功"**，因为允许未定义符号
（`-undefined dynamic_lookup`）。但这样的二进制在设备上会遇到
**`libgcc_s` re-export 解析失败**。

**解法**（三步）：

```
1. 链接出 tmux，用 llvm-nm -u 收集所有未定义符号
2. 从设备的 libncursesw dylib 里收集它导出的符号，做差集
       → 剩下的就是"系统符号"
3. 把系统符号写进 libSystem.tbd（tapi-tbd-v3 格式），重新链接
       → dyld 以 two-level 方式绑定
```

**这正是"止住 iOS 10 上 libgcc_s re-export 失败"的手段**
——即 `docs/uuidgen.md` §7 里 BigBoss `uuid` 死于同一个问题，
而我们有解法的原因。

> **`libSystem.tbd` 是手写桩**（`$IOS_STUBDIR/libSystem.tbd`）。
> **两条注意**：
> - `class-dump` 移植时把 SDK 官方的 tbd 拷成 `sdk-libSystem.tbd`
>   并入白名单，**没有覆盖这个手写的**（见 `docs/class-dump.md` §4）
> - **SDK 模式下仍需这个手写桩**：SDK 自带的 `libSystem.tbd` 是
>   re-export 壳，cctools ld64 追设备绝对路径必炸（`toolchain.md` §16）

## 5. libevent 的特殊处理

| 项 | 说明 |
|---|---|
| `fix_libevent_sources` | 来自 `tmux/patches/fixups.sh` 的源码修正 |
| **`event-config.h` 手工提供** ★ | **libevent 的 configure 输出无法正确描述这个目标** → 直接用 `tmux/patches/event-config.h` 覆盖 `include/event2/event-config.h` |
| 裁剪 | `--disable-openssl`、regress、samples、libevent-install 全关 |
| **安装 legacy 头** | tmux ≥ 3.8 用**旧式 `<event.h>` API**，所以 `include/event.h`、`evdns.h`、`evhttp.h`、`evrpc.h`、`evutil.h` 也要装（它们只是再引入 `event2/` 下的） |

## 6. ncurses

`get_ncurses_headers` **从设备上拉 ncurses 头**（同 vim 的做法），
libncursesw dylib 也走设备副本。详见 `docs/vim.md` WALL 1 与 `docs/less.md` §2。

## 7. 相关文件

| 文件 | 作用 |
|---|---|
| `tmux/build.sh` | **构建 + 三项基建职责** |
| `tmux/patches/fixups.sh` | libevent 源码修正 |
| `tmux/patches/event-config.h` | libevent 的手工配置头 |
| `sysroot-overlay/` | Darwin ABI 修正（sysroot 组装的真相来源） |
| `docs/nmap.md` §4 | sysroot-overlay 的成体系修复清单 |
