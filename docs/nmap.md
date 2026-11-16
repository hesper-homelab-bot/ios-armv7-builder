# nmap 7.95 移植专项（armv7 iOS 10.3.3）

> 包：`nmap_7.95-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`nmap/build.sh`（**全仓库墙最多的移植**）
> 本文记录**状态、八道墙的要点、以及它倒逼出的 sysroot 修复**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 7.95（**nmap + ncat，不含 nping**） |
| 包名 | `nmap_7.95-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools`；数据文件在 `share/nmap/`（`nmap-services` 等） |
| 静态性 | **全静态**：libpcap + openssl + zlib + pcre2 + lua + libdnet + liblinear 全是 `.a` |
| Depends | 仅 `firmware` |

**定位**：本仓库**侵入性最强**的移植。nmap 会构建**五个捆绑库**
（pcre2、lua、libdnet、liblinear、nsock/nbase/libnetutil），
外加它自己的 C++ 核心，**每一个都踩到了 Linux 宿主默认值或 sysroot 缺口**。

## 2. 依赖链

```
libpcap（先跑 libpcap/build.sh）
openssl 4.0.3
zlib 1.3.1（git/build.sh 会建）
        ↓
nmap 7.95（捆绑 pcre2 / lua / libdnet / liblinear / nsock）
```

另需宿主侧 `cxx-wrapper.sh`（nmap 核心是 C++）。

## 3. 八道墙（要点）

| # | 墙 | 要点 |
|---|---|---|
| 1 | **捆绑 pcre2 没有预生成的 configure** | 需先在宿主 `autoreconf -fi`；其 libtool 链接想要 `-soname` dylib（ld64 用不上）→ `--disable-shared` |
| 2 | **五个捆绑库的归档 ld64 不认** | liblua.a / liblinear.a / libnsock.a / libnbase.a / libnetutil.a 都是**普通 GNU ar** 产物，会被 ld64 **静默忽略**（`toolchain.md` §2）→ 构建后**每个归档**都用 `llvm-ar-21 --format=darwin` 重打 |
| 3 | **libdnet 后端靠撒谎的探测选** | ① **route**：`linux_procfs` 探测假成功 → 钉死 `ac_cv_dnet_route_h_has_rt_msghdr=yes` + `ac_cv_dnet_linux_procfs=no`，改用 `route-bsd.c`（设备真正的后端）；② **arp**：stripped Makefile 里**硬编码**了 Linux 的 `arp-ioctl.c` → sed 成 Darwin 的 `arp-bsd.c`；③ **intf**：需要 `<sys/sockio.h>` 的 `SIOCGIFCONF` 等，探测跑在该头进仓库之前 → 事后在 `include/config.h` 里 `#define HAVE_SYS_SOCKIO_H 1` |
| 4 | **sysroot 自身的 Linux 味儿缺口** | 见 §4（这一项倒逼出了 `sysroot-overlay/` 的成体系修复） |
| 5 | **`$(CC) -MM` 被 wrapper 当成未知 flag** | nsock 的 `makefile.dep` 规则跑 `$(CC) -MM`，wrapper 不认识就转发成完整编译+链接 → clang 把**依赖列表写进了每个被扫描的 `.o`**（ASCII 污染）。wrapper 现已原样透传 `-M/-MM/-MD/-MMD`；脚本还会**主动删除**早期被污染的目标文件 |
| 6 | **OpenSSL 4 让 ASN1 不透明、X509 accessor 变 const** | nmap 7.95 和 ncat 仍直接戳字段 → 打补丁（幂等）。`OPENSSL_atexit` 在 OpenSSL 4 已移除 |
| 7 | **nsock 引擎表选中了 epoll** | 来自 musl `sys/epoll.h` 的探测（**头文件存在，但系统调用不存在**）→ 在 `nsock/include/nsock_config.h` 里 `#undef HAVE_EPOLL`，nsock **回退到 kqueue，而 iOS 内核真的提供 kqueue**（与 nginx 同一结论，见 `docs/nginx.md` §2） |
| 8 | **musl 的 `bits/ioctl.h` 用了 Linux 语义的 `_IO/_IOR/_IOW/_IOWR`** ★最深 | 所有用这些宏构造 ioctl 号的 BSD 头（`net/bpf.h` 的 `BIOCSETIF`、`sockio.h` 的 `SIOCAIFADDR`…）都**静默拿到垃圾 request code**，而且**取值还会随头文件包含顺序变化**！修法：`bits/ioctl.h` 改为 include `<sys/ioccom.h>`（BSD 宏），并无条件带上 Darwin 的 tty 号。与墙 #4 同类但**深一层** |
| 8b | **musl 的 `SO_BINDTODEVICE`** | musl `sys/socket.h` 定义了 `SO_BINDTODEVICE (25)`——Linux 专有 sockopt，iOS 内核以 `EAFNOSUPPORT` 回应；nbase 的 `socket_bindtodevice()` 被该宏 `#ifdef` 守卫着，于是**每次扫描都打两遍** `Setting of SO_BINDTODEVICE failed ... (42)`。宏已从 sysroot 头移除（Darwin 用 `IP_BOUND_IF` 做源接口选择），警告消失 |

## 4. sysroot 的成体系修复（本移植的最大副产品）

nmap 倒逼出 `sysroot-overlay/` 的一批**永久性**修复（细节见该目录头部注释）：

| 项 | 问题 | 修法 |
|---|---|---|
| `sys/ioctl.h` | 带了 **Linux 的 `SIOCGIFCONF (0x8912)`** 块 | 移除；改由 XNU 的 `bsd/sys/sockio.h` 提供真正的 BSD 值 |
| `net/route.h` | （musl 版本）没有 `rt_msghdr` | 换成 XNU 的 `bsd/net/route.h` |
| `assert.h` | 调 `__assert_fail`（musl），但 **libSystem 不导出它** | 改为 `__assert_rtn`（**设备实测验证**） |
| `netdb.h` | 带了 glibc 的 `NI_/AI_/EAI_` 值 | 改用 Libinfo 的值。**注意 `NI_NUMERICHOST` 在 Darwin 是 2，不是 1！** |
| `netinet/in.h` | 缺 `IPPROTO_ICMPV6` 等 | 追加 XNU 值 |
| `netinet/in6.h` | 缺 RFC 3542 的 `IPV6_*` 选项常量 | 补齐 |
| `net/if.h` | 缺 `struct ifaliasreq` | 补（`sockio.h` 的 `SIOCAIFADDR` 要对它取 `sizeof`） |
| `sys/un.h` | 缺 `SUN_LEN` | 补 |
| `unistd.h` / `getopt.h` | `getopt_long*` 声明与 nbase/getopt.h 的 const 性不兼容 | 统一为 `char **`（不是 `char *const []`） |

> 这批修复是**跨包受益**的——后来所有需要 BSD ioctl / 路由 / 接口信息的
> 移植都因此少踩坑。

## 5. 相关文件

| 文件 | 作用 |
|---|---|
| `nmap/build.sh` | 构建（**八道墙全文**在注释里） |
| `nmap/make-deb.sh` | 打包（数据文件、双签名） |
| `sysroot-overlay/` | 本移植倒逼出的 sysroot 修复（跨包受益） |
| `docs/nginx.md` §2 | kqueue 是 iOS 真正提供的事件引擎（与墙 #7 同一结论） |
