# Vim 9.1 移植专项（armv7 iOS 10.3.3）

> 包：`vim_9.1.0000-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`vim/build.sh`（**六道 WALL**，403 行）
> 本文记录**六道墙的要点**。Vim 是**终端类移植的模板**
> （curses 策略被 less/tmux 沿用）。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 9.1.0000（终端版 Vim） |
| 包名 | `vim_9.1.0000-1_iphoneos-arm.deb` |
| 安装前缀 | `/var/mobile/tools`；运行期树在 `share/vim/vim91` |
| 产物 | Mach-O armv7 `vim`（`LC_VERSION_MIN_IPHONEOS 10.3`），链接设备自己的 libSystem 与 `libncursesw.5.dylib` |
| 别名 | 包内含 `ex`/`vi`/`view`/`rview`/`rvim`/`vimdiff` 软链 |

**环境契约**（与 `tmux`/`wget` 相同）：

```
IOS_LD64    cctools-port 的 x86_64-apple-darwin*-ld
LD64_LIBS   那个 ld64 需要的 LD_LIBRARY_PATH（libdispatch、tapi）
LD64        作为 IOS_LD64 的别名被接受
DEVICE      ssh 主机名，**仅在需要重新拉取 ncurses 头时使用**
```

## 2. 六道 WALL

### WALL 1（a）：sysroot 没有 ncurses 头

sysroot 是 musl 衍生的，**完全没有 ncurses 头**。而 Vim 没有
`<ncurses.h>` / `<term.h>` 就无法构建。

**设备的 ncurses 是 5.7，宽字符 API 在 `/usr/include/ncursesw`。**
做法（与 tmux 相同）：**从设备上一次性拉下来**。

`ensure_ncurses_headers()` 会检查 sysroot 是否已有，没有就
`ssh <device>` 打 tar 包拉 `ncurses.h` / `curses.h` / `term.h` /
`ncurses_dll.h` / `nc_tparm.h` / `termcap.h` / `unctrl.h` / `eti.h` /
`panel.h` / `menu.h` / `form.h` / `ncursesw`。

### WALL 1（b）：**真正咬人的那个** —— `#ifdef` 语义陷阱 ★

> **这是全部六道墙里最阴的一道。**

`os_unix.c` 对 **include** 和 **use** 用了**不同的守卫**：

```c
/* include 处 */
#if defined(HAVE_SYS_SYSCTL_H) && defined(HAVE_SYSCTL)
#  include <sys/sysctl.h>
#endif

/* 使用处 —— 只有 HAVE_SYSCTL 一个条件！ */
#ifdef HAVE_SYSCTL
    ... CTL_HW ... sysctl(...) ...
#endif
```

**于是"直觉操作"会踩坑**：既然"musl sysroot 没有 `sysctl.h`"，
那就强制 `ac_cv_header_sys_sysctl_h=no`——**结果 use 块照样被编译**，
却没有声明：

```
os_unix.c:577:11: error: use of undeclared identifier 'CTL_HW'
os_unix.c:583:6: error: call to undeclared function 'sysctl'
```

**而 sysroot 其实自带**一个手工适配过的 Darwin `sys/sysctl.h`。

> **通用教训**：`#ifdef HAVE_X` 语义下，**`#define X 0` 是无效的**
> （必须 undef）；反过来，**只压 include 的探测会留下裸奔的 use 块**。
> 同类陷阱在 python3 移植也踩过（见 `docs/python3.md`）。

### WALL 2：`make install` 会用宿主的 `strip`

Makefile 里 `#STRIP = strip` 是**注释掉的**，所以裸跑 `make install`
会执行**宿主的 `/usr/bin/strip`**——本机上是 `x86_64-linux-gnu-strip`，
**对 armv7 Mach-O 操作**。

GNU strip **不认 Mach-O**：轻则报错，**重则把文件搞坏**。

**修法**：`make install STRIP="$LLVM_STRIP"`（`llvm-strip` 懂 Mach-O
且对 armv7 ABI 正确）。

> 备选方案 `STRIP=/bin/true` 保留符号也行，只是二进制更大。
> 选 `llvm-strip` 是为了包更小。

### WALL 3：ncurses 的**链接**（curses 策略的原始出处）★

cc-wrapper **把 `-lncursesw` 丢在地上**（它位于"Darwin 上一切都在
libSystem 里"的列表）——对 `-lc`/`-lm` 是对的，**但这里错了**：
libncursesw **绝对不是** libSystem 的一部分。

**逃生通道**：wrapper 的 **`IOS_DYLIBS`** 变量——它**追加原始链接对象**，
并把 `*.dylib` 归类为链接输入、把路径交给 ld64。

效果：ld64 因此记录一条
`LC_LOAD_DYLIB /usr/lib/libncursesw.5.dylib`，并把需要的
**10 个 termcap 符号**（`tgetent`/`tgetstr`/`tgoto`/`tputs`/`UP`/`BC`/
`PC`/`ospeed`/…）**two-level 绑定**到它上面，而不是留给 dynamic_lookup。

### WALL 4：`make` 需要宿主工具，但要分清哪些能用

| 允许 | 不允许 |
|---|---|
| 顶层 Makefile 用**宿主 `cc`** 跑几个 configure 期辅助程序；调用宿主的 `install-sh`/`sed`/`awk`/`sh` —— **正确且预期**（它们**生成源码**如 `auto/pathdef.c`，不是目标文件） | 让宿主的 **`strip` 或 `ar`** 碰**目标文件** |

所以：`AR`/`RANLIB` **钉死**为 Darwin 版 wrapper；`STRIP` **在 install 时钉死**（WALL 2）。

（`make` 还会跑 `./link.sh`，它会移除一些库重新链接。）

### WALL 5：未定义符号**必须分类**，不能靠"链接成功"

`-undefined dynamic_lookup` 意味着**缺什么都"链接成功"**。
**链接干净的二进制仍可能在设备 dyld 里 `Symbol not found` 而 abort。**

所以 `audit_symbols()` 把**每个**未定义符号分类：

```
每个符号必须满足其一：
  ① 由设备的 libncursesw 导出（我们链接的那个 dylib）
  ② 是我们预期 libSystem 提供的
否则 = 移植 bug，在宿主上追查，而不是等到设备上
```

> 这就是 `tools/check-undefined.sh` 门禁的思想源头。

### WALL 6：辅助脚本要分两层检查

**设备有** `/bin/sh`、`/bin/bash`、`awk`、`sed`；
**设备没有** perl、python、ruby、lua、tclsh、node。

所以包里每个脚本都要查，**分两个层级**：

| 层级 | 判定 |
|---|---|
| `$PREFIX/bin/*` —— **用户实际会运行的** | **硬失败**。`vimtutor` 是 `#!/bin/sh` 没问题；这里若出现 `#!/usr/bin/perl` 就是**出师未捷** |
| `$PREFIX/share/vim/vim91/tools/*` —— 上游的可选开发者工具 | 按上面同样的标准分级处理 |

## 3. 构建后自检

```sh
file "$STAGE/.../vim" | grep -q 'Mach-O armv7'
    || die "staged vim is not Mach-O armv7 -- did a host tool touch it?"
```

**这道断言直接防 WALL 2 类事故**（宿主工具污染目标文件）。

## 4. 相关文件

| 文件 | 作用 |
|---|---|
| `vim/build.sh` | 构建（**六道 WALL 全文**） |
| `vim/make-deb.sh` | 打包 |
| `docs/less.md` §2 | curses 策略的沿用 |
| `docs/tmux.md` | 同款 ncurses 拉取与 sysroot 组装（源头） |
