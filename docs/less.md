# less 668 移植专项（armv7 iOS 10.3.3）

> 包：`less4_668-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`less/build.sh`
> 本文记录**curses 策略（vim 先例）、设备 dylib 的显式链接、以及 tarball vs git 树**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 668 |
| 包名 | `less4_668-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools/less/less`（`bin/` 下有软链） |
| 验收 | ✅ 设备翻页冒烟通过 |

## 2. ★ Curses 策略（沿用 vim 先例）

> 详细说明见 `vim/build.sh` 的 WALL 1，以及 `docs/vim.md`。

| 项 | 做法 |
|---|---|
| **头文件** | ncurses 头**已在 sysroot 里**（vim 移植时从设备上拉下来的：`ncurses.h` / `term.h` / `ncursesw/`，**ncurses 5.7 宽字符 API**） |
| **链接** | less 链接**设备自己的** `/usr/lib/libncursesw.5.dylib` |
| **dylib 来源** | 缓存副本 `$HOME/ios-tool/device-libs/libncursesw.5.dylib`，**显式放在链接行上** |

### ⚠️ 为什么必须显式给 dylib 路径

cc-wrapper 会**静默吸收 `-lncursesw`** —— 它位于"libSystem 内"的丢弃列表里，
**而这个判断对 curses 是错的**。

后果：如果不显式给路径，`check-undefined.sh` 审计门禁会**标红
`tgetent`/`tigetstr`**（因为链接时根本没解析）。

**另一个前提**：设备 `/usr/share/terminfo` **存在**（2026-11-14 验证），
所以 less 能在运行期解析 `TERM` 项。

## 3. 源码：用官方 tarball，不用 git 树

```
https://www.greenwoodsoftware.com/less/less-668.tar.gz
```

**理由**：**git 树缺生成的 `configure` / `funcs.h` / `help.c`**，
而官方 release tarball **自带这些预生成文件**。

build.sh **两条路都支持**（`configure` 或 `configure.ac` 都认），
**默认走 tarball**。

## 4. 相关文件

| 文件 | 作用 |
|---|---|
| `less/build.sh` | 构建（curses 策略全文） |
| `less/make-deb.sh` | 打包 |
| `docs/vim.md` | curses 策略的原始出处（WALL 1） |
