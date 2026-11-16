# Python 移植索引（两个版本并存）

> 本文件是**导航页**。细节在 `docs/python3.md`（同一个文档同时覆盖
> 3.13 与 3.14，因为两条流水线 95% 共用）。

## 1. 设备上有什么

| 项 | python3（3.13） | python314（3.14） |
|---|---|---|
| 版本 | 3.13.18 | 3.14.10 |
| 安装路径 | `/var/mobile/tools/python3` | `/var/mobile/tools/python314` |
| 入口 | `/var/mobile/tools/bin/python3` | `/var/mobile/tools/bin/python3.14` |
| deb 包 | `out/python3_3.13.18-1_iphoneos-arm.deb` | `out/python314_3.14.10-1_iphoneos-arm.deb` |
| stdlib | `lib/python3.13/` | `lib/python3.14/` |
| 扩展 `.so` | `lib/python3.13/lib-dynload/` | `lib/python3.14/lib-dynload/` |

两者**可以共存**，包名不同（`python3` / `python314`），互不覆盖。

## 2. 当前状态（2026-11-16）

**两个版本都全功能可用**，53 个 C 扩展 + TLS 1.3。

```
$ python3 -c "import socket,ssl,sqlite3,hashlib,zlib,math"
$ python3 -c "
import socket, ssl
ctx = ssl._create_unverified_context()
s = socket.create_connection(('www.python.org',443), timeout=25)
ss = ctx.wrap_socket(s, server_hostname='www.python.org')
print(ss.version(), ss.cipher()[0])"
TLSv1.3 TLS_AES_128_GCM_SHA256
```

| 功能 | 状态 |
|---|---|
| 解释器 / 标准库 | ✅ |
| 53 个 C 扩展 | ✅ |
| `ssl` / OpenSSL 4.0.3 | ✅ TLS 1.3 实测握手 |
| `sqlite3` 3.54.1 | ✅ |
| `hashlib` / `zlib` / `math` / `socket` | ✅ |
| CA 证书校验 | ⚠️ 设备无 CA 包，需 `_create_unverified_context()` 或自备 `SSL_CERT_FILE` |

## 3. 两个必须知道的坑

### 3.1 8 字节原子（**头号大坑**）

Apple armv7 ABI 给 `int64_t` 的**自然对齐是 4 字节**，而 ARM 的
`ldrexd`/`strexd` **要求 8 字节对齐** → 非对齐的 8 字节原子直接 **SIGBUS**。

**症状**：`socket.socket()` 100% `Bus error: 10`，且**不产生崩溃报告**。

**修法**：`patches/patch-atomic-armv7-align.py`。
**必跑**，详见 `docs/python3.md` 与 `docs/toolchain.md` §19。

### 3.2 Apple SystemLog 劫持 stdout

`TARGET_OS_IPHONE` 下 `sys.stdout` 变成 `<SystemLog>`，`print` 无输出
而 `os.write(1)` 正常。两个版本位置不同：

- 3.13：`pylifecycle.c` 的 `USE_APPLE_SYSTEM_LOG`
- 3.14：`initconfig.c` 的 `USE_SYSTEM_LOGGER_DEFAULT`（另有运行时
  `-X use_system_logger` 开关）

## 4. 从零重建

```sh
cd ~/ios-tmux-builder
export IOS_SYSROOT=~/ios-tool/iPhoneOS10.3.sdk
export IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib

# 1) 补丁（两个都要）
python3 python3/patches/patch-atomic-armv7-align.py \
        ~/scratch/python3/src<VER>/Include/cpython/pyatomic_gcc.h
python3 python3/patches/patch-cpython-ios-armv7.py ~/scratch/python3/src<VER>

# 2) 构建
PYTHON_SRC=~/scratch/python3/src<VER> BUILD_PYTHON=<同 minor 宿主 python> \
  ./python3/build.sh

# 3) 打包
PYTHON_OBJ=<构建树> PYTHON_SRC=~/scratch/python3/src<VER> ./python3/make-deb.sh
```

> `obj/` 是单一目录，两个版本**交替构建会互相覆盖**。并存的版本请用
> 独立构建树（本项目 3.13 用 `~/scratch/python3/obj313`）。

## 5. 相关文档

| 文档 | 内容 |
|---|---|
| `docs/python3.md` | **主文档**：13 道墙、死锁分析、原子根因、3.14 差异、全部验收输出 |
| `docs/toolchain.md` §19 | 8 字节原子陷阱（跨项目通用，node/ffmpeg 也适用） |
| `python3/patches/README.md` | 补丁脚本用法 + configure 补丁 + 通用坑清单 |
| `python3/build.sh` | 构建脚本（注释即文档） |
| `python3/make-deb{,-314}.sh` | 打包脚本 |
