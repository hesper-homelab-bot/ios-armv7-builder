# OpenSSL 4.0.3 交叉编译（armv7 iOS 10.3.3）——2026-11-16 定型

## Configure 行（关键参数）

```sh
CC=.../tools/cc-wrapper.sh AR=.../tools/darwin-ar RANLIB=.../tools/darwin-ranlib \
CROSS_TOP=/tmp/ios-cross CROSS_SDK=iPhoneOS10.3.sdk \
perl ./Configure ios-cross no-shared no-dso no-tests no-docs \
  -D__ARM_MAX_ARCH__=7 --prefix=/var/mobile/openssl4
```

- `no-shared`：只要静态库
- `no-dso`：不建 provider 动态模块（其链接会触发 text-reloc 错误）
- **`-D__ARM_MAX_ARCH__=7`**：让 `crypto/armcap.c` 走真实探测分支
  （否则 `OPENSSL_cpuid_setup` 编译成空函数，`OPENSSL_armcap_P` 恒为 0）
- **不要 `no-asm`**：要 NEON/AES/SHA 汇编（性能）

## 必须打的补丁

1. **perlasm 的 armcap 间接寻址 → 常量**（`patch-perlasm-armcap.py`）
   8 个 `.pl` 文件里的 `.word OPENSSL_armcap_P[-.Llocal]` + 解引用链，
   改成 `mov rX,#1`。原因：PIC 相对写法在 `-undefined dynamic_lookup`
   下 clang 集成汇编器拒绝；绝对寻址在 Mach-O bundle 里触发
   "illegal text reloc"。常量消除了两种冲突（A6X 确实有 NEON）。

2. **`atomic_compat.c` + `atomic_alias_pic.s`**（本目录）
   设备 libSystem 没有 `__atomic_*`。要点：
   - **跳板必须用尾调用 `b`，绝不能用 `bl`**——`bl` 覆盖 LR，
     被调函数返回时地址与参数寄存器全部错乱
     （实测 `my_atomic_load(size=1, dest=NULL)` → SIGSEGV at 0x100）
   - `is_lock_free` **必须返回 true**：`crypto/init.c:374` 以
     `lock=NULL` 调 `CRYPTO_atomic_load`，只有 lock-free 分支会填充结果
   - 8 字节原子拆成两个 32 位。**注意根因表述（2026-11-16 晚修正）**：
     早先这里写"设备 8 字节原子静默失败"，实测**是 SIGBUS 硬崩**——
     Apple armv7 ABI 给 int64_t 只有 4 字节自然对齐，而 ldrexd/strexd
     要求 8 字节对齐。拆半依然正确，只是理由要对。证据与探针见
     `docs/toolchain.md` §19 与 `tools/probes/probe-atomic-align.c`。
   - 编译：`cc-wrapper.sh -c -mthumb -o atomic_alias_pic.o atomic_alias_pic.s`

3. **GF2m 汇编**：关闭或从归档移除（其绝对寻址在 bundle 里非法）
   ```sh
   llvm-ar d lib/libcrypto.a libcrypto-lib-armv4-gf2m.o
   ```

## 使用方式

`libcrypto.a` / `libssl.a` 产出后，任何消费者（python3 的 `_ssl`/`_hashlib`、
其他链接 OpenSSL 的程序）在链接时必须显式带上：

```sh
<path>/atomic_alias_pic.o <path>/atomic_compat.o
```

因为 `-undefined dynamic_lookup` 不会为了满足引用而主动拉取归档成员。
