# mosh 1.4.0 移植专项（armv7 iOS 10.3.3）

> 包：`mosh_1.4.0-4_iphoneos-arm.deb` · **真机验证完成**
> 构建脚本注释即详细文档：`mosh/build.sh`（222 行注释，墙列表全文在此）
> 本文记录**状态、用法、五层雷与结论**；细节指向 build.sh，不重复。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | mosh 1.4.0 + **libprotobuf 3.20.3**（静态） |
| 包名 | `mosh_1.4.0-4_iphoneos-arm.deb` |
| 安装位置 | `/var/mobile/tools/bin/{mosh-client,mosh-server}` |
| 验收 | ✅ **Termius 手机连接正常**（用户 2026-11-13 确认） |

mosh 是**原型级移植**：`mosh/build.sh` 的 222 行注释是本仓库最详实的构建
文档，后续所有 autoconf 型移植都从它受益。

## 2. 依赖链（顺序不能错）

```
① host protoc（宿主，必须与目标 libprotobuf 同版本）
        ↓ 生成 .pb.cc/.pb.h
② libprotobuf 3.20.3（目标，静态）
        ↓
③ mosh 1.4.0（目标）
```

**为什么必须自举 protoc**：mosh 1.4.0 的 release tarball **不带**
生成的 `.pb.cc/.pb.h`（`src/protobufs` 下只有 `.proto`），所以宿主的
`protoc` 是**必需品**。而 protobuf 生成的代码**内嵌运行时版本检查**，
必须与目标 `libprotobuf` **同版本**——apt 的 3.21 和 3.20.3 **不能混**。
所以从 3.20.3 源码自举：

```sh
./configure --prefix=$HOME/ios-tool/protobuf-host --disable-shared
make -C src protoc
```

**为什么是 3.20.3**：protobuf **3.21+ 已经没有 autotools 了**，
3.20.3 是最后一个还带 `configure --host=...` 的版本。静态构建。

## 3. 五层雷（全部设备实测定位）

对应 handover 记录的五条，细节见 `mosh/build.sh`：

| # | 雷 | 修法 |
|---|---|---|
| 1 | `exit=22` / 源码树消失 | release URL 前缀错——是 **`mosh-`** 不是 `v-`，404 |
| 2 | **configure 探测四连骗** | ① protoc（PATH 里的宿主版被误用）；② OpenSSL 走了宿主库（需 `PKG_CONFIG_LIBDIR`）；③ `AC_CHECK_LIB` 裸 `-lcrypto`（预置 `ac_cv_lib_crypto_*`）；④ wcwidth（XSI 宏需**成组**定义）。详见 `docs/toolchain.md` §9 |
| 3 | `config.h` 被 make 反复重生成 | 修正必须做在 **`config.h.in` 模板** + 触摸 autotools 链（`aclocal/autoconf/autoheader` regen 链，§13） |
| 4 | `HAVE_PLEDGE` | 必须**未定义**（不是 0）——`#ifdef` 陷阱 |
| 5 | `-DNDEBUG` / link 细节 | `-DNDEBUG` 必须与 protobuf 库一致（`InternalMetadata` 析构）；zlib 用**显式 `.a`**（wrapper 丢 `-lz`）；`pledge`/`recvmmsg` 等 **6 个符号**进 `libios-compat.a` 优雅降级 |

### 3.1 补充：build.sh 里的四条硬结论

- **`HAVE_PTHREAD` 要手工 `#define 1`**：`-lpthread` 探测失败（wrapper 丢弃），
  但 pthreads 确实在 libSystem 里。
- **`CPPFLAGS="-D_POSIX_C_SOURCE=200809L"` 必须给在命令行**：
  automake 在 configure 时就把 CPPFLAGS **烤进 `src/Makefile`**，
  `make CPPFLAGS=...` 会被**静默忽略**。
- **`HAVE_MACH_ABSOLUTE_TIME` 要 `#undef`**：根本没有 mach 头文件；
  且它是**烤死的值**而非模板行，改 `config.status` 里的 `D["..."]` 后
  重跑 `./config.status src/include/config.h`（直接改 config.h 会被洗掉）。
- **`HAVE_PLEDGE` 同理**（OpenBSD 专有系统调用）。

## 4. ⚠️ 64 位原子：这次**没有**踩雷（重要交叉证据）

> 本节与 `docs/toolchain.md` §19 互为印证，是理解 Apple armv7 原子问题的关键。

移植时做了"64 位原子恐慌"的预案（node 墙 #11 的教训），但**实际没成真**：

反汇编 `arena.o` 发现，clang 把 `std::atomic<uint64_t>` **内联成了真正的
`ldrexd/strexd` 重试循环**，**从不调用设备上那个坏掉的 `___atomic_load_8`
libcall**（`toolchain.md` §4）。

**判别方法**：看**反汇编**（`grep ldrd` 会对 64 位参数搬移产生假阳性），
**不要看 `nm`**。

`node/patches/shims/` 的 `at64.o` 与 `tools/shims/` 的 `c8fixed.o`
（2026-11-19 公共化）仍**防御性地链着**（成本低），
以防 libcall 形式在别处冒出来。

**为什么这条重要**：它精确划出了原子雷区的边界——
- **内联的** `ldrexd/strexd` 重试循环 → 安全（编译器自己处理对齐/重试）
- **走 libcall 的** `__atomic_*`（compiler-rt） → **非对齐即 SIGBUS**

python3 撞的正是后者。详见 `docs/toolchain.md` §19。

## 5. 设备侧注意事项

- **Termius 连接即起 `mosh-server`**；`ps` 验证要抓 `mosh-server new`。
  **会话只活 4 秒是正常的**——server 起来即脱离 ssh（正常流程，非故障）。
- 调试期装过日志 wrapper（`/var/mobile/tools/bin/mosh-server` 脚本），
  已被 deb 覆盖还原为真二进制；`/tmp/moshwrap.log` 可删。
- 我方测试会话（端口 60200）若仍在，会 60s 超时自退，**无需处理**。

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `mosh/build.sh` | 构建（**全文注释即权威墙列表**，222 行） |
| `mosh/make-deb.sh` | 打包 |
| `mosh/patch-mosh.py` | 源码补丁 |

## 7. README 实录迁入（2026-11-19）


Mosh (mobile shell) keeps a terminal session alive across roaming and
sleeping clients: one short ssh exchanges the key, then everything rides a
 UDP stream that survives IP changes and long disconnections.  On the iPad
this is the difference between Termius reconnecting from scratch on every
wake and a session that simply continues.

Device-verified end to end: `mosh-server` survives the ssh channel closing
(the one thing dropbear's pty teardown used to kill), binds its UDP socket
on the SSH_CONNECTION IPv4, and a real Termius client holds a working
session.  The wall list lives in `mosh/build.sh`; the ones that mattered:

- **release URL**: the tag is `mosh-1.4.0`, not `v1.4.0` — a wrong prefix
  returns 404, `curl -f` turns that into exit 22, and a wiped source tree
  cannot re-download
- **autoconf probes lie four different ways under cross-compilation**:
  protoc (PATH-only lookup — `export PROTOC`), OpenSSL (pkg-config silently
  answers with the HOST library — set `PKG_CONFIG_LIBDIR`), `AC_CHECK_LIB`
  (a bare `-lcrypto` cannot link — pre-seed the autoconf cache variables),
  and feature-macro pairing (wcwidth is XSI: `_XOPEN_SOURCE=700` must
  accompany `_POSIX_C_SOURCE`)
- **`config.h` regenerates on every make**; header corrections go into the
  `config.h.in` *template*, plus the autotools regen chain (aclocal /
  autoconf / autoheader) must be quashed by equalizing mtimes — otherwise
  the first make discards every fix (toolchain.md §10/§13)
- **`HAVE_PLEDGE` must be undefined, not 0**: mosh tests it with `#ifdef`,
  so even a value of 0 compiles the OpenBSD-only `pledge()` call in
- **`-DNDEBUG` must match the protobuf library** (built with NDEBUG by its
  configure default): otherwise InternalMetadata's out-of-line destructor
  is referenced but provided by no archive member, and dyld kills the
  forked server on the first message destruction
- **zlib is linked by explicit archive path** (`$ZLIB/libz.a`): the
  cc-wrapper drops `-lz` (assuming it lives in libSystem — it does not) and
  the `-L`+`-lz` search does not resolve through the wrapper chain
- **six symbols ship as graceful stubs** (`libios-compat.a`): recvmmsg /
  sendmmsg (no such syscalls in iOS 10.3.3's XNU, dragged in by OpenSSL's
  static socket helpers) and the terminfo quartet (no ncurses on iOS);
  they return ENOSYS / curses ERR instead of dying

The post-link symbol audit (`tools/check-undefined.sh`) and the
device-probe whitelist generator (`tools/probe-symbols.sh`) came out of
this port; every build now runs the audit as a gate.

