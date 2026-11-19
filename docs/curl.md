# curl 8.16.0 移植专项（armv7 iOS 10.3.3）

> 包：`curl4_8.16.0-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`curl/build.sh`
> 本文记录**状态、依赖、三个必修坑与签名教训**；细节指向 build.sh。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 8.16.0 |
| 包名 | `curl4_8.16.0-1_iphoneos-arm.deb` |
| 安装路径 | `/var/mobile/tools/curl`（`PREFIX=/var/mobile/tools`） |
| 依赖 | **自编 OpenSSL 4.0.3 静态库**（libssl.a + libcrypto.a） |
| 静态性 | 全静态，运行期**不依赖** `libssl.dylib` |

**设计原则**：所有包都装在 `/var/mobile` 下，**不碰 `/usr`**。这样
设备自带的 sshd 等一切照旧，卸载就是 `rm -rf /var/mobile/openssl4`。

## 2. 依赖关系

```
openssl/build.sh  →  libssl.a + libcrypto.a（静态）
                          ↓
curl/build.sh     →  src/curl（静态链接上述归档）
```

curl 的 configure 期望 `<prefix>/lib/libssl.a`，而 OpenSSL 构建树把归档
放在**根目录**。build.sh 里建了软链补齐布局：

```sh
mkdir -p "$OSSL/lib"
ln -sfn ../libcrypto.a "$OSSL/lib/libcrypto.a"
ln -sfn ../libssl.a    "$OSSL/lib/libssl.a"
```

## 3. 三个必修坑（全部经设备崩溃定位）

| # | 坑 | 症状 | 修法 |
|---|---|---|---|
| 1 | **`SOCK_NONBLOCK` / `SOCK_CLOEXEC` 在 iOS 10 不存在** | musl 把它们定义成 Linux 风格的 type flag（`0x80000` 等）；curl 把 `SOCK_NONBLOCK` **或进** `socket()` 的 type 参数 → 内核以 `EINVAL` 拒绝 → **每个连接在 ~1ms 内失败**，报 `Failed initialization` | 在 sysroot 里 **undef 这两个宏**，curl 便回退到 `fcntl(F_SETFL)` |
| 2 | **`struct sockaddr` 需要 Darwin 的前导 `sa_len` 字节** | （`sockaddr_in` 同理要有 `sin_len`）缺了它，`inet_ntop()` 会在 offset 0 读到一个 16 位 family，返回 `EAFNOSUPPORT` | 用带 `sa_len` 的 Darwin 版头 |
| 3 | **configure 的 link 探测恒真** | 我们链接时用 `-undefined dynamic_lookup`，导致 curl 探测到一批 **iOS 上根本没有**的 Linux 专有函数：`eventfd`、`pipe2`、`accept4`、`recvmmsg`、`sendmmsg`、`getpass_r`、`gsasl`… | configure 后在 `lib/curl_config.h` 里逐个 `#undef`（见 build.sh 的 for 循环）。同类问题见 `docs/toolchain.md` §8 |

> 坑 1 是**最隐蔽**的：它不崩溃、不报错，只是"连接秒失败"，
> 极易误判成网络问题或 OpenSSL 问题。

## 4. ⚠️ 签名教训：那个"宿主 ldid 不可靠"的传说是假的

`curl/make-deb.sh` 的 `sign()` 函数里留了一段重要的历史注释，值得单列：

**旧代码**：

```sh
ldid -S "$dst" 2>/dev/null || true     # ← 吞掉一切
```

后果：**打包出去的二进制根本没签名**。而未签名的 Mach-O 会被设备在
`main()` 之前以 **SIGKILL 干掉，且不产生崩溃报告**。

这直接催生了"宿主 ldid 偶尔产出设备会杀的二进制"（`Killed: 9`）这个
**民间传说**——真相**不是宿主 ldid 不可靠，而是这行把失败吞了**。

**现在的代码**：`ldid` 不在 PATH 就**拒绝打包**，失败必须响亮。

> 这条与 `~/.dsh/AGENTS.md` 的部署三件套呼应：
> **无崩溃报告的 SIGKILL = 签名问题**，优先查签名。

## 5. 设备侧用法

```sh
# HTTPS 需要指定 CA 文件（设备 /etc/ssl/certs 是空的）
export SSL_CERT_FILE=/etc/ssl/cert.pem
```

> 设备 `/etc/ssl/certs/` 目录**为空**，所以任何走系统 CA 路径的程序
> （curl / python3 的 ssl 等）都需要自带证书包或显式指定。

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `curl/build.sh` | 构建（三坑的推导过程在注释里） |
| `curl/make-deb.sh` | 打包（**含签名教训**，与 openssl 一起出两个包） |

## 墙:keepalive 误设 TCP_NOPUSH 的 5 秒 cork(2026-11-19,SDK 迁移)

**症状**:设备 curl 请求"能收到回包但延迟很久";loopback 上 TTFB 恒定
~5.01s(connect 毫秒级);`-v` 两条 `Failed to set TCP_KEEPINTVL/KEEPCNT
on fd 5: errno 42`(ENOPROTOOPT)。

**根因**(tcpdump lo0 + 服务端时间戳 + 选项空间探针,全链路实证):musl
派生 sysroot 的 `netinet/tcp.h` 是 Linux 选项号——`TCP_KEEPIDLE=4` 在
Darwin 撞 `TCP_NOPUSH=0x04`(设备实测 0x4 可设!),curl 默认 keepalive
设置把 socket **cork 住**,请求在内核压 ~5s(NOPUSH 定时器)才放行;
`TCP_KEEPINTVL=5/TCP_KEEPCNT=6` 是死号 → errno 42。服务端全部无辜
(nginx/python/Go 即时响应,sockprobe 裸 C 4-9ms)。

**修法**:按 2026-11-15 拍板**迁移 SDK sysroot**
(`IOS_SYSROOT=$HOME/ios-tool/iPhoneOS10.3.sdk`,`IOS_STUBDIR=$HOME/ios-tool`
锚 -lSystem,真 Apple 头常量天然正确);另链 `tools/shims/c8fixed.S`
(libcrypto 2026-11-16 重建引入 `___atomic_is_lock_free` 引用,墙#7 同源,
check-undefined 205/205)。终验:default keepalive 5.01s → **2.4ms**,
errno 42 归零,HTTPS 200。

**部署新教训(三件套增补)**:`cp` 原地覆盖**已签名**二进制后,即使内容/
签名 blob md5 完整,内核仍拒载(依赖 inode 状态,机制未深挖);**覆盖后
必须对目标重新 `ldid -S`**,或直接走 deb(dpkg 解包 = 新 inode + rename +
postinst 重签,天然免疫——实测对照)。本次 3 次 Killed:9 假信号的真凶。

**根因自查方法论**:分段计时(curl -w)→ tcpdump lo0 看内核视角哪个包
迟到 → 服务端加时间戳分清 send/recv 侧 → 选项空间探针(python3 逐号
setsockopt)→ 开关实验(--no-keepalive 一发命中)。
