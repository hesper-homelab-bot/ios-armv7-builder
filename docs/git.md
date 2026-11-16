# git 2.51.2 移植专项（armv7 iOS 10.3.3）

> 包：`git_2.51.2-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`git/build.sh`
> 本文记录**状态、依赖链、为什么不用 autoconf、Linux 宿主默认值泄漏清单**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 2.51.2 |
| 包名 | `git_2.51.2-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools`（`/var/mobile/tools/bin/git`） |
| 静态性 | **全静态**：libz + libcurl + libssl + libcrypto 全是 `.a` |
| Depends | 仅 `firmware`（无运行期库依赖） |

安装的二进制包括 `bin/*` 与 `libexec/git-core/` 下的**全部 helper**。

## 2. 依赖链（构建顺序不能错）

```
zlib 1.3.1        →  libz.a      （纯 C，秒级）
openssl 4.0.3     →  libssl.a + libcrypto.a
curl 8.16.0       →  libcurl.a
        ↓
git 2.51.2        →  bin/git + libexec/git-core/*
```

**zlib 的特殊性**：git **不能没有 zlib**（没有 `--without-zlib` 选项）。
本仓库其他包大多回避 zlib，所以这是树里**第一个静态 libz**。
zlib 是纯 C、无 syscall，交叉构建只要几秒。

> ⚠️ zlib 构建后必须**转换归档格式**：GNU thin archive 会被 ld64
> **静默忽略**（见 `docs/toolchain.md` §2）。build.sh 用
> `llvm-ar-21 --format=darwin` 重打，并在替换前**校验成员数 > 0**。

## 3. 为什么 git 不走 autoconf

git 的 `configure` 探测在**这个目标上撒的谎比通常还狠**，而且构建在
Linux 宿主上时，`config.mak.uname` 的 `ifeq ($(uname_S),Linux)` 分支会把
**宿主机的默认值**烤进去——**但我们的 target 是 iOS，不是构建机**。

所以这里用**手写的 `config.mak`**（与 sqlite 直接走 amalgamation 同款取舍）。

## 4. Linux 宿主默认值泄漏清单（关键）

`config.mak` 是**在 `config.mak.uname` 之后**被 include 的，所以里面的
普通赋值能覆盖掉那些错误的宿主机默认值。被覆盖的项：

| 设置 | 原因 |
|---|---|
| `HAVE_SYNC_FILE_RANGE =` | **iOS 没有 `sync_file_range` 系统调用** |
| `HAVE_SYSINFO =` | iOS 也**没有 sysinfo** |
| `HAVE_PLATFORM_PROCINFO =` | **iOS 完全没有 procfs**（`/proc` 不存在） |
| `PROCFS_EXECUTABLE_PATH =` | 同上 |
| `COMPAT_OBJS := $(filter-out compat/linux/procinfo.o, …)` | 把 Linux 专有的 procinfo.o 从目标里剔除 |
| `NO_STRLCPY =` | iOS libSystem **有** `strlcpy`（BSD），不要编 git 的 compat 副本 |
| （arc4random） | iOS libSystem **原生提供 `arc4random_buf`**；而 `getrandom` 在 iOS 10 不存在，**首次调用会在 dyld 报 symbol not found 而 abort** |
| `NO_SETITIMER = YesPlease` | git 的进度条用 `setitimer`；iOS 上其实存在但探测会误导，且该功能只是装饰性 → 关掉 |

## 5. 其他裁剪（`config.mak`）

设备上**没有任何脚本解释器**，所以：

```make
NO_GETTEXT = YesPlease      # 无 gettext
NO_TCLTK   = YesPlease      # 无 Tcl/Tk
NO_PERL    = YesPlease      # 无 perl
NO_PYTHON  = YesPlease      # 无 python（注意：这是 git 构建期的，与
                            # 本仓库的 python3 包无关）
NO_EXPAT   = YesPlease
NO_ICONV   = YesPlease
NO_REGEX   = YesPlease      # 用 git 自带 regex；sysroot 里没有可用的可探测
NO_APPLE_COMMON_CRYPTO = YesPlease   # 链我们的 OpenSSL 4，不用 Apple CommonCrypto
NEEDS_CRYPTO_WITH_SSL = YesPlease
NO_INSTALL_HARDLINKS = YesPlease
HAVE_ALLOCA_H = YesPlease
```

## 6. TLS 信任库

`libcurl.a` **不像安装好的 curl 二进制那样读 `SSL_CERT_FILE`**，
所以 git 直接跑会报 `unable to get local issuer certificate`。
`make-deb.sh` 为此在包里放了**默认信任库**。

> 与 `docs/curl.md` §5 同一个根源：设备 `/etc/ssl/certs/` 是空的。

## 7. 打包与双签名

`make-deb.sh` 沿用 wget/curl 的双签名约定：

> 注释里写着「宿主 ldid 偶尔产出设备会杀的二进制」——这条**传说的真相**
> 见 `docs/curl.md` §4：不是 ldid 不可靠，而是签名失败被 `|| true` 吞了。
> 设备侧用设备自己的 ldid 再签一次始终可靠。

git 二进制**很多**（`bin/*` 加 `libexec/git-core` 的 helper），所以打包
脚本会 `find` 整个 staging 树，逐个 `file | grep Mach-O` 判定后签名。

## 8. 相关文件

| 文件 | 作用 |
|---|---|
| `git/build.sh` | 构建（zlib 引导 + 手写 config.mak + 覆盖清单全文） |
| `git/make-deb.sh` | 打包（全树 Mach-O 签名、TLS 信任库） |
