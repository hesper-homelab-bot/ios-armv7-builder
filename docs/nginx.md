# nginx 1.26.3 移植专项（armv7 iOS 10.3.3）

> 包：`nginx4_1.26.3-5_iphoneos-arm.deb` · 服务化完成
> 构建脚本注释即详细文档：`nginx/build.sh`（154 行注释，墙列表全文在此）
> 本文记录**状态、用法、运维与结论**；踩坑细节指向 build.sh，不重复。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 1.26.3（stable） |
| 包名 | `nginx4_1.26.3-5_iphoneos-arm.deb` |
| 安装前缀 | `/var/mobile/tools/nginx` |
| 服务化 | ✅ launchd 守护 `com.hesper.nginx`，postinst 自动 load |
| 验收 | ✅ gzip 实测返回 200 |
| **当前运行状态** | ⚠️ **设备侧已停用**（2026-11-14，用户要求），见 §5 |

## 2. 关键结论：`--crossbuild` 是命门

nginx 的 configure 是**手写 sh 脚本**（非 autoconf），它按**构建机的 `uname -s`**
选目标 OS。在 Linux 上会走 Linux 分支（epoll / Linux sendfile / eventfd /
SO_REUSEPORT），产出的二进制在 iOS 上根本不能跑。

**解法不是改 `auto/os/conf`，而是告诉 configure 真相**：

```sh
--crossbuild=Darwin:16.7.0:armv7
```

这会让 `NGX_PLATFORM` 生效，configure 转而 source `auto/os/darwin`，得到
`NGX_HAVE_KQUEUE` + `NGX_HAVE_CLEAR_EVENT` + kqueue 事件模块 + Darwin
sendfile 链。**kqueue 正是 iOS 内核真正提供的引擎**（nmap/nsock 在
`HAVE_EPOLL` 被 undef 后也回退到它，见 `docs/nmap.md` 墙 #7）。

## 3. 四个坑（细节见 `nginx/build.sh`）

| # | 坑 | 要点 |
|---|---|---|
| 1 | **探针恒真 + 运行探针不可能执行** | cc-wrapper 用 `-undefined dynamic_lookup`，编译+链接型探测永远成功；而 `ngx_feature_run=yes` 的探针是 armv7 Mach-O，宿主 x86 Linux 跑不了 → nginx 报 "found but is not working" 并**把 NGX_HAVE_* 从 `objs/ngx_auto_config.h` 里漏掉**（静默假阴，如 Darwin sendfile / EVFILT_TIMER）。**别试图让探针诚实，configure 后直接补 `ngx_auto_config.h` 的宏块**。同类失败见 `docs/toolchain.md` §8 |
| 2 | **PCRE2/zlib 走 `--with-pcre=DIR` / `--with-zlib=DIR`** | 这是唯一干净的路：`auto/lib/pcre/conf` 靠 `$PCRE/src/pcre2.h.generic` 判定，然后直接把 `$PCRE/.libs/libpcre2-8.a` 塞进 `CORE_LIBS`；zlib 同理。**无需 -l、无需 -L、无需 sed 生成的 Makefile**。但 pcre2 归档**必须是 Darwin flat 格式**——ld64 会静默忽略 GNU thin archive（`toolchain.md` §2）；nmap 留下的那份格式正确，所以只校验成员数而非盲信 |
| 3 | **`--with-openssl=DIR` 千万别用** | nginx 期望那是**源码树**，会自己去 `$OPENSSL/.openssl/` 配置并构建。我们的 OpenSSL 4.0.3 是**已交叉编译好的**（libssl.a/libcrypto.a 在顶层，头在 include/）。不带该选项会让 nginx 走自动探测 `-lssl -lcrypto`，在 dynamic_lookup 下探测"成功"、置上 NGX_SSL/NGX_OPENSSL，**但缺 include 路径**。用 `--with-cc-opt -I$OSSL/include` 补头，并确保归档在链接行上；真正打开 SSL 的是 `--with-http_ssl_module` |
| 4 | **cc-wrapper 会丢 `-lz` 这类"libSystem 内"的库** | wrapper 按 macOS 事实丢弃固定 `-l*` 列表（`-lz` 在列），但 **iOS 10 没有这个 re-export**；`-lpcre2-8` 无 `-L` 也解析不了。git 的 libz.a 撞过同款。解法：通过 `--with-ld-opt` 把 OpenSSL 两个归档以**显式路径**加进链接行（静态归档对 ld64 也讲顺序，符号仍未被满足时才会拉成员，所以放最后） |

## 4. 打包与部署

**双重签名约定**（wget/curl 同款）：宿主打 payload 时签一次，`postinst`
在设备上用**设备自己的 ldid** 再签一次。理由：宿主产出的签名偶尔在设备上
exec 失败（**SIGKILL 且无崩溃报告**，见 `~/.dsh/AGENTS.md` 部署三件套）。

`postinst` 还负责：
- 用设备 ldid 重签
- 修正 owner/mode
- 创建 `logs/ tmp/ conf/ share/nginx/html/` 等运行期目录
  （dpkg 不保留我们自己设定的属主信息之外的东西）

目录布局（nginx 相对 prefix 解析）：

```
/var/mobile/tools/nginx/
├── bin/nginx
├── conf/nginx.conf
├── logs/
├── share/nginx/html/
└── tmp/{client_body,proxy}/
/var/mobile/.local/bin/            # 启动脚本
/Library/LaunchDaemons/com.hesper.nginx.plist
```

## 5. 运维：启停（设备侧）

### 停用（2026-11-14 已执行）

用户要停的是**设备侧** nginx（监听 8080），**不是宿主机的**。

```sh
launchctl unload /Library/LaunchDaemons/com.hesper.nginx.plist
```

> **踩过的坑**：当时误停了**宿主机** systemd nginx，当日已复原
> （`systemctl enable --now nginx`，active + enabled 双确认）。
> **教训：停服务前先确认是哪一侧的设备。**

**开机不自启**：iOS 10 launchd 的 `-w` 参数**不落 overrides**
（`/var/db/launchd/db/com.apple.launchd/overrides.plist` 不存在），
必须往 plist 写 `<key>Disabled</key><true/>`。

> 改写 plist 用了 `/var/mobile/tools/bin/node`（**绝对路径**）——
> root 非登录 shell 的 PATH 只有 `/usr/bin:/bin`，裸 `node` 找不到。

**改前备份**：
`/var/mobile/.local/etc/backup-nginx/com.hesper.nginx.plist.pre-disable`

**副作用**：plist 被改后 `dpkg -V nginx4` 会报该文件 md5 不符
（**预期行为，非损坏**）。

### 重新启用

去掉 plist 里的 `Disabled` 键（或恢复备份），然后：

```sh
launchctl load /Library/LaunchDaemons/com.hesper.nginx.plist
```

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `nginx/build.sh` | 构建（**墙列表全文**在注释里，154 行） |
| `nginx/make-deb.sh` | 打包（含 postinst/prerm、双签名、目录布局） |
| `nginx/patch-nginx.py` | 源码补丁 |
| `nginx/crossanswer.sh` | 交叉探测应答 |
| `nginx/nginx.conf` | 默认配置 |
| `nginx/nginx-daemon.sh` | 守护启动脚本 |
| `nginx/com.hesper.nginx.plist` | launchd 定义 |
| `nginx/pcre2-config` | PCRE2 探测垫片 |
