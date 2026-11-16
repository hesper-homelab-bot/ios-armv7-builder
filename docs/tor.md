# tor 0.4.8.14 移植专项（armv7 iOS 10.3.3）

> 包：`tor4_0.4.8.14-1_iphoneos-arm.deb`
> 构建脚本注释即详细文档：`tor/build.sh`
> 本文记录**全静态栈、探针压制清单、以及两条固化下来的结构性规避**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 0.4.8.14 |
| 包名 | `tor4_0.4.8.14-1_iphoneos-arm.deb` |
| 安装前缀 | `/var/mobile/tools/tor` |
| 静态栈 | libevent 2.1.12 + OpenSSL 4.0.3 + zlib 1.3.1 —— **全静态** |
| 验收 | ✅ 设备 `--version` / `--verify-config` 通过；**249 个未定义符号全部设备实测绑定** |

## 2. 依赖链

```
libevent 2.1.12   →  ~/ios-tool/build-ios/install（tmux 时代产物）
OpenSSL 4.0.3     →  libssl.a + libcrypto.a（带汇编版，见 docs/openssl.md）
zlib              →  **设备的 libSystem 自带**（动态 -lz；wrapper 有意丢弃 -lz）
        ↓
tor 0.4.8.14
```

**裁剪**：关闭 dirauth 模块（不需要当目录权威）、关闭 asciidoc
（无 manpage），其余全默认。

## 3. 源码获取（tarball 难找）

- `dist.torproject.org` ❌ 不可达
- GitHub 镜像 ❌ 不可达／**只有 alpha tag**（陈旧）
- ✅ **解决方案**：用 **Debian pool** 的 `tor_0.4.8.14.orig.tar.gz`

## 4. 探针压制清单（20+ 项）

`dynamic_lookup` 下链接探测**恒真**（`toolchain.md` §8），tor 的 configure
会因此认下一批 iOS 上不存在的函数。全部按 `ac_cv_func_*=no` 压制：

| 类别 | 被压制的符号 |
|---|---|
| **安全擦除** | `SecureZeroMemory`、`RtlSecureZeroMemory`、`explicit_bzero`、`memset_s` —— 设备 iOS 10 **只真有 `memset_s`**，但 sysroot 的 `string.h` 没声明它。全压掉，走 tor 自己的可移植 memset 擦除路径 |
| **凭据/权限** | `getresuid`、`getresgid`、`cap_set_proc`、`prctl` |
| **Linux 专有** | `eventfd`、`pipe2`、`accept4`、`get_current_dir_name` |
| **其他** | `gethostbyname_r`、`libscrypt_scrypt`、`pthread_condattr_setclock`、`readpassphrase`、`timingsafe_memcmp`、`gnu_get_libc_version` |

> `check_decl` 对"未声明"符号**反而返回 yes**（反向逻辑）+ `check_func`
> 恒真 —— 两者叠加是这套压制的根因。

## 5. ★ 两条固化下来的结构性规避

### 5.1 环境变量**每个一条独立 `export`**，绝不用续行链

> **本文件里"注释吞掉续行反斜杠导致 env 断链"的事故发生了三次。**
> 已固化为**结构性规避**：自包含语句没有续行链，注释可以随便插。
> configure 之后有**断言兜底**。

**这是全仓库级的教训**（`~/.dsh/AGENTS.md` 也记了"续行链中插注释"这个
已知 bug 模式）。写 shell 时：**注释永远不要出现在续行链中间**。

### 5.2 `-DNULL=0`，**不能**写成 `((void*)0)`

sysroot 的手写头（`sys/socket.h` 等）不提供 `NULL`（`stddef` 链缺失）。

值**必须用 `0`**：configure 的 shell 会把**未加引号的括号当元字符**，
一旦 `AC_PROG_CC` 被毒倒，**整条探针链会回落到宿主 gcc**（2026-11-14 实录）。

### 5.3 configure 后必须断言 CC 是 wrapper

> **`CC` 失联 = 探针跑在宿主 gcc 上，全部结论不可信。**
> （libevent 明明在却报找不到，就是这么来的。）

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `tor/build.sh` | 构建（压制清单 + 断言全文） |
| `tor/make-deb.sh` | 打包 |
| `docs/toolchain.md` §8 | dynamic_lookup 恒真探针（跨包通用） |
