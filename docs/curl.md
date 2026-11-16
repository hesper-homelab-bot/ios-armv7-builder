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
