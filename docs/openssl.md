# OpenSSL 4.0.3 移植专项（armv7 iOS 10.3.3）

> 包：`openssl4_4.0.3-1_iphoneos-arm.deb` · **带汇编（NEON/AES/SHA）构建**
> 回写资料：`openssl/patches/`（CONFIG-NOTES.md + 三个补丁文件）
> 本文记录**定型 Configure 行、三项必打补丁、以及消费者必须注意的链接约定**。

## 1. 状态

| 项 | 值 |
|---|---|
| 版本 | 4.0.3 |
| 包名 | `openssl4_4.0.3-1_iphoneos-arm.deb` |
| 安装前缀 | `/var/mobile/openssl4` |
| 产物 | `libcrypto.a` + `libssl.a`（**静态**，带汇编优化） |
| 下游消费者 | curl、git、wget、tor、python3（`_ssl`/`_hashlib`）、nginx |

## 2. 上游现状

`ios-cross` / `iphoneos-cross` 目标在 OpenSSL 4.x **仍然存在**
（`Configurations/15-ios.conf`，`asm_arch` 为 armv4），但**上游从不测试它们**。
所以本地必须做若干调整。

## 3. 定型 Configure 行

```sh
CC=.../tools/cc-wrapper.sh AR=.../tools/darwin-ar RANLIB=.../tools/darwin-ranlib \
CROSS_TOP=/tmp/ios-cross CROSS_SDK=iPhoneOS10.3.sdk \
perl ./Configure ios-cross no-shared no-dso no-tests no-docs \
  -D__ARM_MAX_ARCH__=7 --prefix=/var/mobile/openssl4
```

| 参数 | 为什么 |
|---|---|
| `no-shared` | 只要静态库 |
| `no-dso` | 不建 provider 动态模块（其链接会触发 text-reloc 错误） |
| **`-D__ARM_MAX_ARCH__=7`** | 让 `crypto/armcap.c` 走**真实探测**分支。否则 `OPENSSL_cpuid_setup` 被编译成空函数、`OPENSSL_armcap_P` 恒为 0 |
| **不要 `no-asm`** ⚠️ | 要 NEON/AES/SHA 汇编（**性能**）。历史上曾误加 `no-asm` 而被当作"唯一出路"，实为误判 |
| （本地调整） | conf 里的 `-arch armv7` 需移除（Linux clang 只认 `-target`）；`CROSS_TOP`/`CROSS_SDK` 把 legacy `-isysroot` 指到我们的 sysroot |

## 4. 三项必打补丁

### 4.1 perlasm 的 armcap 间接寻址 → 常量

**文件**：`openssl/patches/patch-perlasm-armcap.py`（8 个 `.pl`）

**问题**：perlasm 生成的 ARM 汇编用了 `.word OPENSSL_armcap_P[-.Llocal]`
加解引用链。这在我们的链接模型下**两头堵**：

- PIC 相对写法 → `-undefined dynamic_lookup` 下 **clang 集成汇编器拒绝**
- 绝对寻址 → Mach-O bundle 里触发 **illegal text reloc**

**修法**：把整个 armcap 间接寻址**替换成 `mov rX,#1`**（常量）。
常量同时消除两种冲突——**而 A6X 确实有 NEON**，所以置 1 是事实正确的。

**验证**：该脚本已在**原始 tarball** 上端到端跑通。

### 4.2 `atomic_compat.c` + `atomic_alias_pic.s`

设备 libSystem **没有 `__atomic_*` 运行时**（generic 版本的
load/store/compare_exchange 都缺），所以要自带实现。**三个关键约束**：

| 约束 | 说明 |
|---|---|
| **跳板必须用尾调用 `b`，绝不能用 `bl`** ★ | `bl` 会**覆盖 LR**，被调函数返回时**地址与参数寄存器全部错乱**。实测症状：`my_atomic_load(size=1, dest=NULL)` → SIGSEGV at 0x100。这个 bug 花了**最长时间**才定位（最后靠源码插桩） |
| **`is_lock_free` 必须返回 `true`** ★ | `crypto/init.c:374` 以 **`lock=NULL`** 调用 `CRYPTO_atomic_load`，**只有 lock-free 分支会填充结果**。返回 false 就走需要锁的分支，而锁是 NULL |
| 8 字节原子拆成两个 32 位 | Apple armv7 的 8 字节原子有对齐陷阱，详见 §5 |

**编译**：

```sh
cc-wrapper.sh -c -mthumb -o atomic_alias_pic.o atomic_alias_pic.s
```

### 4.3 GF2m 汇编

其绝对寻址在 bundle 里非法 → **关闭或从归档移除**：

```sh
llvm-ar d lib/libcrypto.a libcrypto-lib-armv4-gf2m.o
```

## 5. ⚠️ 8 字节原子：这里是**对齐陷阱**，不是"静默失败"

> **2026-11-16 晚修正**：本节早先的表述（"设备 8 字节原子静默失败"）
> 源自本目录 `CONFIG-NOTES.md` 的早期记录，**已被设备探针推翻**。
> 正确根因是**对齐**——详见 `docs/toolchain.md` §19。

Apple 32 位 ARM ABI 给 `int64_t` 的自然对齐是 **4 字节**，而 ARM 的
`ldrexd`/`strexd` 要求 **8 字节对齐** → 非对齐即 **SIGBUS**。

设备探针实录：

```
sizeof(int64_t)=8   _Alignof(int64_t)=4
__atomic_load_n(<4 字节对齐的 int64>)  →  Bus error: 10
```

**对 OpenSSL 的影响**：`atomic_compat.c` 里把 8 字节原子拆成两个 32 位
**仍然是对的**——只是理由要改成"避开非对齐 `ldrexd`"，而不是"绕过
静默失败"。拆半本身没有问题。

## 6. 消费者必须知道的链接约定 ★

**任何链接 OpenSSL 静态库的程序**（python3 的 `_ssl`/`_hashlib`、
curl、git、wget、tor、nginx…）在链接行上**必须显式带上这两个目标文件**：

```sh
<path>/atomic_alias_pic.o <path>/atomic_compat.o
```

**原因**：`-undefined dynamic_lookup` **不会为了满足引用而主动拉取归档成员**。
一旦漏掉，症状是在设备上 **dlopen 时**才报
`Symbol not found: _OPENSSL_armcap_P`（或 atomic 相关符号），
而不是链接期报错——**排查成本很高**。

## 7. 相关文件

| 文件 | 作用 |
|---|---|
| `openssl/build.sh` | 构建入口 |
| `openssl/patches/CONFIG-NOTES.md` | 定型 Configure 行 + 补丁清单 |
| `openssl/patches/patch-perlasm-armcap.py` | 8 个 `.pl` 的 armcap 改造（已端到端验证） |
| `openssl/patches/atomic_compat.c` | `__atomic_*` 实现（`is_lock_free` 返回 true） |
| `openssl/patches/atomic_alias_pic.s` | 跳板（**尾调用 `b`**） |
| `docs/toolchain.md` §19 | 8 字节原子的对齐根因（跨项目通用） |
