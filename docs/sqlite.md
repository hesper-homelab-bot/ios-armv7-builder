# SQLite 3.54.1 移植专项（armv7 iOS 10.3.3）

> 包：`sqlite3_3.54.1-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`sqlite/build.sh`
> 本文记录**为什么故意不跑 configure、特性取舍、以及为什么必须私有前缀**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 3.54.1（`sqlite-autoconf-3540100`） |
| 包名 | `sqlite3_3.54.1-1_iphoneos-arm.deb` |
| 产物 | `sqlite3`（shell）+ `libsqlite3.a`（静态，供设备端 C 构建） |
| 安装路径 | `/var/mobile/tools` |
| 依赖 | **完全静态**，无运行期库依赖（**连 zlib 都没有**，见 §4） |

## 2. 核心取舍：**故意不跑 configure**

`sQLite` 用**直接 amalgamation** 路线（与 git 用手写 `config.mak` 同款理由）：
**在这个目标上，每个 autoconf 探测都在撒谎**。

| 探测类型 | 为什么会骗 |
|---|---|
| **链接型** | cc-wrapper 用 `-undefined dynamic_lookup` 链接，**任何**符号探测都"成功"——探测**永远不会发现** iOS 10 缺某个符号 |
| **运行型** | 交叉编译**跑不了**，`AC_RUN_IFELSE` 只能退回悲观猜测。而 SQLite 的这类探测**基于 glibc/BSD 的 FILE 内部结构**，我们 musl 衍生的 sysroot 根本没有 |
| **函数嗅探** | sqlite 的 configure 还会嗅探 `localtime_r`、`usleep`、`fdatasync`… 它会按**链接探测的结果**回答"yes"，而不是按**设备实际导出**回答 |

**amalgamation 就是两个翻译单元**（`sqlite3.c` + `shell.c`）加一个生成的
`sqlite3.h`。直接对它们调用 cc-wrapper，**比跑一次 configure 再手工订正
输出更简单，也更诚实**。

## 3. 特性集（与上游 sqlite-autoconf 默认对齐）

保留上游默认开启的扩展，让 shell 行为与桌面版一致：

| 宏 | 作用 |
|---|---|
| `SQLITE_ENABLE_FTS5` | 全文检索 v5（纯 C，无依赖） |
| `SQLITE_ENABLE_RTREE` | R*tree 索引（纯 C，无依赖） |
| `SQLITE_ENABLE_COLUMN_METADATA` | `.schema` / `table_info` 辅助 |
| `SQLITE_ENABLE_DBSTAT_VTAB` | dbstat 虚拟表 |
| `SQLITE_ENABLE_MATH_FUNCTIONS` | `sin`/`cos`… 等 SQL 函数 |
| `SQLITE_ENABLE_JSON1` | 3.38+ 已进核心，此处保留以明示 |

### 关键：`SQLITE_THREADSAFE=0`

单线程 shell，**彻底移除互斥层**。

> **这同时是对 8 字节原子问题最安全的回答**：设备上的 64 位原子
> **读**有对齐陷阱（见 `docs/toolchain.md` §19）。`THREADSAFE=0` 让
> sqlite 在热路径上**完全不取原子**。
>
> **注意根因表述**：`sqlite/build.sh` 的注释里写的是
> "libcall `___atomic_load_8` 是空函数，64 位原子读静默返回垃圾"——
> 那是**早期认知**；实测是**非对齐即 SIGBUS**。结论（`THREADSAFE=0`
> 最安全）不变，但理由要按 §19 更新。

### `SQLITE_OMIT_LOAD_EXTENSION`

动态加载会走 `dlopen`——iOS 上 `dlopen` 存在，但**无法加载未签名的代码**。
省略它还顺带**从链接里去掉 `dlopen`/`dlsym` 需求**。

（注：`SQLITE_OMIT_PROGRESS_CALLBACK=0` 是**显式保留**该功能；python3 的
`_sqlite3` 依赖 `sqlite3_progress_handler`，而某些静态构建会省略它——
python3 侧为此补了 stub，见 `docs/python3.md`。）

## 4. ⚠️ `-lz` 不要加（虽然这里也不需要）

cc-wrapper 会**静默丢弃 `-lz`**——它位于"Darwin 上全在 libSystem 里"的
丢弃列表，这在 macOS 上成立，但 **iOS 10 不成立**（zlib 在独立的
`libz.dylib`）。

sqlite **只在定义了 `SQLITE_HAVE_ZLIB` 时才需要 zlib**，此处没有定义，
所以 shell 无 zlib 依赖。

> **如果将来需要**：把 `$ZLIB/libz.a` 作为**显式归档对象**链接，
> **不要**用 `-lz`（做法见 `docs/git.md` §2）。

## 5. 为什么必须装在私有前缀（`/var/mobile/tools`）

**不能装到 `/usr/bin`**：

- iOS **已经自带** `libsqlite3.dylib`，系统其他组件链接它
- 往 `/usr/bin` 放一个不同的 `sqlite3` 二进制 → **会遮蔽系统那个**
  （任何经 PATH 解析的东西都会拿到我们的）
- 替换那个 dylib → **会把系统搞坏**

私有前缀让 shell 和归档**完全隔离**。

## 6. 设备侧背景：系统自带的那个是坏的

> 设备 `/usr/lib/libsqlite3.0.dylib` 是一个**悬空符号链接**，
> **不提供任何符号**（`_sqlite3_*` 全部被 dyld 拒绝——2026-11-16 用
> `tools/probe-symbols.sh` 验证）。

所以 python3 的 `_sqlite3` 模块**必须链我们这份静态库**，并且用**它自己的
3.54.1 头文件**（而不是 SDK 的 3.16.0），以保证头与库一致。

## 7. `libsqlite3.a` 的归档格式

必须产出 **Darwin 格式**归档——ld64 **静默忽略 GNU 归档**（`toolchain.md` §2），
而 `llvm-ar` 默认写 GNU。所以 build.sh 里显式 `--format=darwin`
**并校验成员数 > 0**。

## 8. 相关文件

| 文件 | 作用 |
|---|---|
| `sqlite/build.sh` | 构建（不跑 configure 的完整理由 + 特性集） |
| `sqlite/make-deb.sh` | 打包（含"为什么不装 /usr/bin"的说明） |
| `python3/build.sh` | 消费者：`_sqlite3` 链接本静态库的配方 |
