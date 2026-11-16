# lsof 4.99.7 移植专项（armv7 iOS 10.3.3）

> 包：`lsof_4.99.7-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`lsof/build.sh`
> 本文记录**为什么新版反而更容易、唯一的关键头文件、以及"内核 ABI 别手改"的教训**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 4.99.7 |
| 包名 | `lsof_4.99.7-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools/bin/lsof` |

## 2. 核心结论：新版比老版**容易得多**

lsof 是个"看起来老、实际不难"的移植，而**原因决定了整个方案**：

| 版本 | 实现方式 | 在 iOS 10 上的命运 |
|---|---|---|
| **4.78**（越狱镜像自带） | **手工解析 `struct kinfo_proc`** | ❌ iOS 10 上**结构布局已不匹配** → 每个 PID 都报 `Cannot allocate memory`。**没救** |
| **4.99.7** | **基于 libproc**：通过 `proc_listpids()` / `proc_pidinfo()` / `proc_pidfdinfo()` 与内核对话——**和 `ps` 用的是同一接口** | ✅ 布局由内核侧保证，**完全不需要内核侧的适配工作** |

> 关键分界：**lsof ≥ 4.80 的 Darwin dialect 才是 libproc 化的**。
> 之前的老版本全靠猜内核结构，换个大版本必崩。

## 3. 唯一的关键头文件：`sys/proc_info.h`

构建需要的一切都是头文件，而且**具体就是这一个**——它定义了
`PROC_PID*` flavors 和内核往调用者缓冲区里拷贝的那些结构体。

sysroot 里已有它，来源是**与 iOS 10.3.x 精确匹配的 xnu tag**
（`xnu-3789.70.16`）。同时 `libproc.h` 现在 **include 它**，
而不是自己手工声明一个子集。

### ⚠️ 铁律：这个头**不要手改**

> 它的结构体**就是内核 ABI**。字段差几个字节**不会编译报错**，
> 而是产出**静默错误的输出**——**这正是 4.78 的死法**。
>
> **必须**从与设备内核匹配的 xnu tag 拷贝（用 `uname -v` 查设备内核版本）。
> 参见 `sysroot-overlay/usr/include/sys/proc_info.h`。

## 4. 构建要点

### 4.1 两个幂等的 dialect 补丁

lsof 以 **tarball** 形式发布，源码树会跨构建复用，而 `patch` 拒绝
二次应用——所以两个补丁都**用 marker 做幂等判定**：

| 补丁 | 作用 |
|---|---|
| `patches/010-dlsof-h-drop-rpc-attr.patch` | `lib/dialects/darwin/dlsof.h` 去掉 rpc/attr 相关 |
| `patches/020-machine-h-ios.patch` | `lib/dialects/darwin/machine.h` 的 iOS 适配（`HASNORPC_H`） |

### 4.2 配置全靠环境变量（Configure 早于 autoconf）

lsof 的 `Configure` **比 autoconf 还老**，所以一切通过环境驱动：

| 变量 | 值 | 为什么 |
|---|---|---|
| `LSOF_VSTR` | **设备实际报告的 `uname -r`**（如 `16.7.0`） | 16.* 分支会映射到 `DARWINV=1600`，而 `-DDARWINV=1600` 才会为 xnu-3789 内核选中正确的条件编译。**不要硬编码** |
| `DARWIN_BASE` | `libproc` | 强制 libproc dialect（Darwin ≥ 8 本来就是默认，写明是让 configure 输出诚实） |
| `LSOF_AR` / `LSOF_RANLIB` | **Darwin 的 ar/ranlib** | GNU ar 归档 ld64 **读不了**（见 `tools/`，同 `toolchain.md` §2） |
| `LSOF_INCLUDE` | `$IOS_SYSROOT/usr/include` | 指向本仓库 sysroot |
| `CONFIG_SITE` | 置空 | lsof 的 Configure **不用** config.site；列在这里是为了防止某个残留 export 假装它有用 |

### 4.3 源码获取

`raw.githubusercontent.com` 从本机**不可靠**；走 github.com 的
codeload tarball 没问题。build.sh 已按此实现。

## 5. 相关文件

| 文件 | 作用 |
|---|---|
| `lsof/build.sh` | 构建（libproc 结论 + 环境驱动配置全文） |
| `lsof/make-deb.sh` | 打包 |
| `lsof/patches/` | 两个幂等 dialect 补丁 |
| `sysroot-overlay/usr/include/sys/proc_info.h` | **内核 ABI 头**（从匹配的 xnu tag 拷贝，勿手改） |
