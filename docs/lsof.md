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

## 6. README 实录迁入（2026-11-19）


lsof is the clearest illustration of why *which kernel interface a program
uses* decides whether it can be ported at all.

The lsof 4.78 that ships in jailbreak images predates the libproc era. It
parses `struct kinfo_proc` out of a `sysctl(KERN_PROC_ALL)` buffer by hand,
and the struct it was compiled against no longer matches the iOS 10 kernel —
so it runs, prints its banner, and then reports `Cannot allocate memory` for
**every** PID. Nothing is wrong with the kernel or the process table; the
program is reading the wrong bytes at the wrong offsets. There is no way to
fix that from outside, and no reason to: since 4.80 the Darwin dialect talks
to the kernel through `proc_listpids()`/`proc_pidinfo()`/`proc_pidfdinfo()` —
the same libproc interface `ps` uses — and iOS exports it.

That moves the whole port into headers, and really into one header:
`sys/proc_info.h`, which defines the `PROC_PID*` flavor numbers and the
structs the kernel copies into the caller's buffer. Those structs are kernel
ABI. A field a few bytes off does not fail to compile — it makes every
answer silently wrong, which is exactly the disease described above. So the
sysroot's copy is taken **verbatim** from the xnu tag matching the device
kernel (`uname -v` says `xnu-3789.70.16~4`, so the tag is `xnu-3789.70.16`;
the `~n` build suffix never changes the headers) — not hand-written, not
borrowed from a newer macOS SDK:

```sh
git clone --depth 1 --branch xnu-3789.70.16 --filter=blob:none --sparse \
    https://github.com/apple-oss-distributions/xnu
cd xnu && git sparse-checkout add --skip-checks bsd/sys/proc_info.h
```

`proc_info.h` drags a small tail of Darwin headers behind it; the overlay
provides minimal versions of each, field-checked against the same tag:
`sys/mount.h` (Darwin `struct statfs` — on iOS 10 the 64-bit-inode layout is
the only one), `sys/un.h` (with `sun_len`, which musl's omits), `sys/`
`kern_control.h`, `netinet/tcp_fsm.h` and `tcp_timer.h` (note: the user-space
`TCPT_*` timer indices differ from the `BSD_KERNEL_PRIVATE` ones in the same
file), `mach/port.h`, `mach/machine.h`, `uuid/uuid.h`, and a Darwin
`sys/param.h` (`MAXPATHLEN` is 1024, not musl's 4096 — `vnode_info_path`
embeds it). `libproc.h` itself now only declares functions and includes
`sys/proc_info.h`; its earlier revision hand-declared a few of those structs
and got `PROC_PIDTBSDINFO` wrong (4 where the kernel says 3) — proof that
hand-copied ABI constants are a bug waiting for a caller.

The source patches are three, all in the darwin dialect: `dlsof.h` drops the
`<rpc/*>` includes (lsof's libproc code never references XDR and iOS exports
no XDR symbols), `machine.h` stops including the host's absolute
`/usr/include/string.h` and defines `HASNORPC_H` so the portmap blocks
compile out, and Configure's unconditional `-lcurses` is removed (nothing in
the dialect calls it and iOS has no curses). Configuration is entirely
environment-driven, because lsof's `Configure` predates autoconf:
`LSOF_VSTR` is the device's `uname -r` (16.7.0 → `DARWINV=1600`, which is
exact for xnu-3789), `DARWIN_BASE=libproc`, `LSOF_INCLUDE` at the sysroot,
and `LSOF_AR`/`LSOF_RANLIB` at the Darwin ar/ranlib — GNU ar archives are
unreadable by ld64.

Two behaviours worth knowing before trusting the output:

* **Root visibility.** As an unprivileged user, lsof sees only its own
  processes; other users' fds — including root daemons and their listening
  sockets — are invisible, exactly as on macOS where lsof ships setuid. Run
  `sudo lsof` for the full picture. This is the kernel enforcing
  `proc_pidinfo`, not a build defect, so do not "fix" it with setuid.
* **Stale objects.** lsof's hand-maintained Makefiles list explicit `.o:`
  dependencies that do not include sysroot headers. After changing anything
  in the overlay, `make clean` first — a stale `print.o` from before a
  header change will link happily and then misreport address families, which
  is how the duplicate-case collisions in its family switch went unnoticed
  for one build.

