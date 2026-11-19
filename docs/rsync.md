# rsync 3.3.0 移植专项（armv7 iOS 10.3.3）

> 包：`rsync4_3.3.0-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`rsync/build.sh`
> 本文记录**增量同步验收、ac_cv 压制清单、以及"探针有罪推定"原则**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 3.3.0 |
| 包名 | `rsync4_3.3.0-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools/rsync/rsync`(+`/usr/bin/rsync`、`/var/mobile/tools/bin/rsync` 链接) |
| 验收 | ✅ **增量同步 291B / 2817 字节**（改 1 加 1 只传增量） |

**立项动机**：部署是日常痛点（此前一切都走 `scp`），rsync 给出**增量传输
+ 可续传**。

**零外部依赖**：3.3.0 在树内**自带 popt、zlib、xxhash**，**没有需要交叉
构建的外部依赖**。

## 2. ★ 用法注意：非登录 shell 的 PATH

```sh
rsync ... # 3.3.0-2 起 /usr/bin/rsync 链接就位,rsync-over-ssh 直接可用
# (旧用法 --rsync-path=/var/mobile/tools/bin/rsync 仍有效)
```

**过 ssh 时必须显式指定 `--rsync-path`**——非登录 shell 的 `PATH`
**不含 `/var/mobile/tools/bin`**。

> 这是设备侧的通用约定（`~/.dsh/AGENTS.md` 也有记：
> **`su mobile -c` 的 PATH 只有 `/usr/bin:/bin`**）。

## 3. 构建要点

| 项 | 说明 |
|---|---|
| 源码 | git 树**自带预生成的 `./configure`**（不需要 autoconf） |
| 交叉 | `--host=<triplet>` 让 autoconf 进交叉模式，run 探针自我默认；**只在 configure 真的卡住时**才补显式 `ac_cv_*` |
| 裁剪 | 首轮构建**不要** openssl/zstd/lz4（可选校验/编解码插件——自带的 md5+zlib 足够）、不要 md2man |
| iconv | 自动探测；sysroot 里没有 `iconv.h` 就自动禁用 |

## 4. ★★ 有罪推定原则（standing rule）

> **"任何 configure 报'找到'的 `ac_cv_func_*`，在通过链接后审计之前，
> 一律视为有罪。"**

**为什么**：cc-wrapper 用 `-undefined dynamic_lookup` 链接，autoconf 经典的
"声明 `char fn();` 然后链接"存在性探针**永远成功**——**哪怕是设备 libSystem
根本没有的函数**。

**实例**：glibc 专有的 `mallinfo2` 就这样"通过"了探测，然后在启动时
以 `struct mallinfo2` 不完整 / dyld 缺符号的形式**死掉**。

**做法**：
1. **主动关掉已知的 glibc-ism**（下面的清单）
2. **`tools/check-undefined.sh` 门禁兜住剩下的**

## 5. `ac_cv_*` 压制清单

| 符号 | 为什么 |
|---|---|
| `mallinfo` / `mallinfo2` | **glibc 专有**；设备 libSystem 两个都没有 |
| `setattrlist` / `getattrlist` / `attropen` | macOS 的 attrlist API。设备**有这些符号**，但 sysroot **没有 `<sys/attr.h>`**（与 lsof 丢掉的是同一个头）。回退到可移植的 `utimes()`；**唯一损失**是同步文件的 `crtime`（补 overlay 的 `sys/attr.h` 可恢复） |
| `chflags` / `lchmod` | **Darwin 专有**；musl 的 `stat.h` 没有声明 |
| `mknod` / `linkat` | sysroot 头没有声明；rsync 回退到 `-1` / 普通 `link()` |
| `acl_get_file` | libacl 探测（另有 `--disable-acl-support`） |
| `utimensat` | **iOS 10 的 Darwin 上不存在**，SDK 头也不声明——恒真探针放进来必炸。回退 `utimes` |
| **`HAVE_GETTIMEOFDAY_TZ=yes`** | ⚠️ **这是一个"yes"覆盖（罕见的真值修正）**：手工 sysroot 的 `sys/time.h` 是 **11 行的最小头，不提供 `NULL`**，导致 `gettimeofday(&tv, NULL)` 探针**因为 `NULL` 失败**，从而误报签名。而本平台**确实是 2 参数形式**（sysroot 的 NULL 缺口，backlog 有记） |

## 6. ★ 结构性规避：注释永不进续行链

> build.sh 里写着：**所有 rationale 注释都放在上面，绝不放进下面的
> 续行链里** —— 因为 `#` 出现在行连接符之后会**吃掉尾部反斜杠**，
> 静默地把**每个环境变量**从 configure 命令上断开。
>
> **这个 bug 在 2026-11-14 吃掉了两次构建**，因此 configure 之后加了断言。

同款规避见 `docs/tor.md` §5.1（那里发生三次）和
`~/.dsh/AGENTS.md` 的已知 bug 模式"续行链中插注释"。

**写法**：全部 override 用**独立 `export` 行**——自包含语句没有续行链，
注释可以随便插。

## 7. 相关文件

| 文件 | 作用 |
|---|---|
| `rsync/build.sh` | 构建（压制清单 + rationale 全文） |
| `rsync/make-deb.sh` | 打包 |
| `tools/check-undefined.sh` | 链接后审计门禁 |
| `docs/toolchain.md` §15 | dynamic_lookup 恒真探针、ac_cv 压制清单、configure 后断言 |

## 墙:rsync-over-ssh 的 PATH(2026-11-20 修复)

dropbear 非交互会话 `PATH=/usr/bin:/bin`,rsync 不在其中——`rsync -e ssh`
远端起 `rsync --server` 报 `command not found`,连接秒断("connection
unexpectedly closed (0 bytes received)")。原设计要求每次显式
`--rsync-path=...`,3.3.0-2 起 postinst 建 `/usr/bin/rsync` 链接,直接
可用(与 curl 的"默认化"先例一致)。验收:push 全量 + 增量(改 1 加 1,
236B) + 拉取,三向全通。
