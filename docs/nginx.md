# nginx 1.31.9 移植专项（armv7 iOS 10.3.3）

> 包：`nginx4_1.31.9-1_iphoneos-arm.deb` · 服务化完成
> 构建脚本注释即详细文档：`nginx/build.sh`（墙列表全文在此）
> 本文记录**状态、用法、运维与结论**；踩坑细节指向 build.sh，不重复。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 1.31.9（mainline，2026-11-19 安全升级，原 1.26.3-5） |
| 包名 | `nginx4_1.31.9-1_iphoneos-arm.deb` |
| 安装前缀 | `/var/mobile/tools/nginx` |
| 服务化 | ✅ launchd 守护 `com.hesper.nginx`，postinst 自动 load |
| 验收 | ✅ 主机侧 curl `GET 200 896B/8ms`、`HEAD 200`（device 本机 curl 8.16 loopback 是**坏仪器**，见 §7） |
| **当前运行状态** | ⚠️ **设备侧停用**（2026-11-14 用户要求省电；2026-11-19 升级后再次确认关闭），见 §5 |

## 1.5 升级记录（2026-11-19：1.26.3-5 → 1.31.9-1）

**安全动机**：1.31.8 及之前受影响一批 CVE（[官方公告](https://nginx.org/en/security_advisories.html)），
major 两个命中我们的模块集：CVE-2026-123007（HTTP/2 flow control 内存破坏）、
CVE-2026-118899（TLS 1.3 请求体读入死循环）；另含 CVE-2026-123633（HTTP/2 UAF）、
CVE-2026-123634（resolver UAF）、CVE-2026-125283（alias+try_files 溢出）等。

**构建墙 #7**：链接期 `check-undefined.sh` 抓到 `___atomic_is_lock_free` 未解析——
设备 libSystem 有 load/store/CAS 三个操作符，唯独没有这个谓词；openSSL 4.0.3 的
threads_pthread.o（11-16 重建后）引用了它。**1.26.3 当时链接干净只是因为早于
libcrypto 重建**。修法：链公共垫片 `tools/shims/c8fixed.S`（node 同款，≤4 且对齐
→1，否则 0；详见 `docs/toolchain.md` §4）。

**patch-nginx.py**：OCSP stapling 补丁对 1.31.9 已过时（上游改用
`i2d_ASN1_INTEGER` 串行化 serial），脚本改为检测后优雅跳过。

**验收**：`check-undefined.sh` 233/233 全解析；dpkg 原地升级（1.26.3-5 over）
+ 设备 ldid 重签成功。浏览器级终验未做（服务按用户要求保持关闭）。

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

## 3. 五个坑（细节见 `nginx/build.sh`）

| # | 坑 | 要点 |
|---|---|---|
| 1 | **探针恒真 + 运行探针不可能执行** | cc-wrapper 用 `-undefined dynamic_lookup`，编译+链接型探测永远成功；而 `ngx_feature_run=yes` 的探针是 armv7 Mach-O，宿主 x86 Linux 跑不了 → nginx 报 "found but is not working" 并**把 NGX_HAVE_* 从 `objs/ngx_auto_config.h` 里漏掉**（静默假阴，如 Darwin sendfile / EVFILT_TIMER）。**别试图让探针诚实，configure 后直接补 `ngx_auto_config.h` 的宏块**。同类失败见 `docs/toolchain.md` §8 |
| 2 | **PCRE2/zlib 走 `--with-pcre=DIR` / `--with-zlib=DIR`** | 这是唯一干净的路：`auto/lib/pcre/conf` 靠 `$PCRE/src/pcre2.h.generic` 判定，然后直接把 `$PCRE/.libs/libpcre2-8.a` 塞进 `CORE_LIBS`；zlib 同理。**无需 -l、无需 -L、无需 sed 生成的 Makefile**。但 pcre2 归档**必须是 Darwin flat 格式**——ld64 会静默忽略 GNU thin archive（`toolchain.md` §2）；nmap 留下的那份格式正确，所以只校验成员数而非盲信 |
| 3 | **`--with-openssl=DIR` 千万别用** | nginx 期望那是**源码树**，会自己去 `$OPENSSL/.openssl/` 配置并构建。我们的 OpenSSL 4.0.3 是**已交叉编译好的**（libssl.a/libcrypto.a 在顶层，头在 include/）。不带该选项会让 nginx 走自动探测 `-lssl -lcrypto`，在 dynamic_lookup 下探测"成功"、置上 NGX_SSL/NGX_OPENSSL，**但缺 include 路径**。用 `--with-cc-opt -I$OSSL/include` 补头，并确保归档在链接行上；真正打开 SSL 的是 `--with-http_ssl_module` |
| 4 | **cc-wrapper 会丢 `-lz` 这类"libSystem 内"的库** | wrapper 按 macOS 事实丢弃固定 `-l*` 列表（`-lz` 在列），但 **iOS 10 没有这个 re-export**；`-lpcre2-8` 无 `-L` 也解析不了。git 的 libz.a 撞过同款。解法：通过 `--with-ld-opt` 把 OpenSSL 两个归档以**显式路径**加进链接行（静态归档对 ld64 也讲顺序，符号仍未被满足时才会拉成员，所以放最后） |
| 7 | **`___atomic_is_lock_free` 设备无导出（墙#7，2026-11-19）** | 依赖来自静态库成员（libcrypto threads_pthread.o），链接期只有 `tools/check-undefined.sh` 能抓；运行期表现是 worker 一进 `CRYPTO_atomic_*` 就被 dyld 杀。链接 `tools/shims/c8fixed.S`（公共垫片）。**教训：静态库重建会让引用漂移，每次链接后必跑 check-undefined** |

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

## 7. 验证仪器的教训（2026-11-19）

- **设备本机 curl 8.16 的 loopback 是坏仪器**：对 `127.0.0.1:8080` 连接、发送
  正常，但永远收不到响应字节（对旧 1.26.3 二进制同样超时）；同一实例对局域网
  主机 curl 响应 `200/6ms`。**网络服务的功能验收一律用主机侧 curl 打设备 IP，
  不要用设备本机 curl**。
- **curl 超时断开后，worker 记 `shutdown() failed (57: Socket is not
  connected) while sending response` 是良性清理日志**，不是发送路径故障的证据。
- **access.log 记了 200 ≠ 客户端收到了**：必须双端对账（服务端日志 +
  客户端 `%{http_code}`/下载字节数）。
- **排障先看 ps 里 master 的二进制路径**：A/B 切换后极易测错对象（本次
  "浏览器正常"其实发生在旧二进制上）；curl 的 URL 别直接用
  `SSH_CONNECTION` 里的 `::ffff:` 前缀地址。

## 8. setproctitle 假阳性全录（2026-11-20 自 toolchain §9.1 原文迁入）

### 9.1 只编译不链接：声明存在 = 探针通过

`auto/unix` 的 `ngx_feature_run=no` 让 setproctitle() 探针**只编译**测试程序。
sysroot-overlay 的 `unistd.h` 里有一行 `void setproctitle(const char*, ...);`
（为别的包准备的），于是 `NGX_HAVE_SETPROCTITLE=1` 被误置。
ngx_setproctitle.h 随即把 `ngx_setproctitle()` 映射到 libc 符号——而
**iOS libSystem 根本不导出它**（实测：`nm -g /usr/lib/libSystem.B.dylib |
grep setproctitle` 为空）。链接居然成功（flat namespace 留下 undefined），
错误推迟到运行期：

```
dyld: Symbol not found: _setproctitle
  Referenced from: .../bin/nginx
  Expected in: flat namespace
```

**信号**：master 进程活着、日志打了 "using the kqueue event method"，
但 worker **立刻消失**、端口无监听、`nginx` 看起来 exit 0。
**修法**：`unset_macro NGX_HAVE_SETPROCTITLE`（走 nginx 自带的 env 方案）。
