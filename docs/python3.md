# python3 移植（CPython 3.13.18 / armv7 iOS 10.3.3）——**已完成上线**

> 2026-11-15 立项当日战报。SDK sysroot 模式（AGENTS 规则 5）。
> 源码 `~/scratch/python3/src313`（3.13.18）；宿主 build-python
> `~/scratch/python3/hostbuild/python`（3.13.18 原生，frozen 生成器必需）。

## 当前状态：**成功上线（2026-11-16）**

设备 kit 第 27 包 `python3 3.13.18-1`（deb 15MB，gzip）。全新 deb 安装后
以 mobile 身份验收：`print(42)`→42、`math.pi`→3.141593、zlib 压缩、
SHA256、json/base64/文件 IO/tempfile/decimal、`os.uname()`→Darwin 16.7.0
**全部通过**。51 个 C 扩展可加载。

**已知缺口**：`ssl` / `_hashlib`（OpenSSL 静态库在 bundle 里有 armv7
text-relocation 问题）；`_sqlite3` 未编（configure 时缺头）。

### 攻克的三个大关（详见下文）

1. **8 字节原子静默失败** → 死锁（见下方专节）
2. **Apple SystemLog 劫持 stdout** → `print` 无输出
3. **cc-wrapper 给 bundle 加 `-e _main`** → 扩展 dlopen 报
   "Symbol not found: _main"

## 已踩的墙（全部有修法记录，见 `python3/build.sh` 注释）

| # | 墙 | 修法 |
|---|----|------|
| 1 | MACHDEP=iOS 强制 --enable-framework | host triplet 改 `armv7-apple-darwin` 走 darwin 路径（设备本质 Darwin 16） |
| 2 | `getaddrinfo bug` 探测是运行型（交叉必假阳） | `ac_cv_buggy_getaddrinfo=no` |
| 3 | AC_CHECK_FUNCS 恒真假阳（dynamic_lookup）40+ 函数 | **审计法**：pyconfig.h 全部 enabled HAVE_* 对设备 tbd 符号集（518 tbd/19 万符号）差集+人工过筛；configure 参数级 `ac_cv_func_<name>=no` |
| 4 | `#ifdef HAVE_X` 语义：`#define X 0` 无效 | 必须用 autoconf undef 形态（首轮实录） |
| 5 | Makefile `pyconfig.h: config.status` 依赖：configure 后 sed 被 make 重生成洗掉 | 压制必须 configure 参数级，不能事后 sed（二轮实录） |
| 6 | clock_nanosleep/clock_settime 的 AC_CHECK_LIB([rt]) **嵌套回退**：func 缓存压了 lib 回退照样恒真 | `ac_cv_lib_rt_clock_nanosleep=no` 同压；上游本有 `ac_sys_system=iOS` 特判（configure.ac 5726 注释），我们 host=darwin 绕 framework 时失守，双压等效 |
| 7 | libmpdec UNIVERSAL 架构表无 arm32 → #error，CONFIG_32 全灭 | make 命令行覆盖 `MODULE__DECIMAL_CFLAGS`+`LIBMPDEC_CFLAGS`（两处定义都要覆盖）= `-DCONFIG_32=1 -DANSI=1` |
| 8 | iOS 10.3 SDK 无 sys/random.h 但 libSystem 有 getentropy | 垫片头 `-include`（getentropy 声明 + sf_hdtr 完整定义 + sendfile 原型——socket.h 把它们藏 `!_POSIX_C_SOURCE` 后，CPython 恒定义 _POSIX_C_SOURCE） |
| 9 | 垫片头无 include guard × CPPFLAGS 重复进链 → 重定义 | 加 guard |
| 10 | **cc-wrapper 通用 bug**：`-framework X` case 双 shift + 循环尾 shift = 多吞一个参数（`-o python` 被吞 → 产物 a.out） | wrapper 改 `FRAMEWORKS+=("$2"); shift 2; continue`（CPython 是首个用 `-framework 对` 的移植） |
| 11 | **Apple armv7 ABI 的 int64/long long 对齐 = 4**（Linux armv7 = 8）→ 结构内 8 字节原子踩未对齐 → EXC_ARM_DA_ALIGN（compiler_rt） | 源码补丁：`pycore_interp_structs.h`（3.14）`interp_count/_code_object_generation/next_stackref/next_unique_id`、`pycore_typeobject.h`（3.13）`interp_count`、`pycore_interp.h`（3.13）`next_unique_id` 全部 `__attribute__((aligned(8)))` |
| 12 | frozen 数据 invalid（_frozen_importlib） | frozen 生成器用 build-python 跑——3.14 marshal 格式 3.13 读不认；宿主原生编 3.13.18 当 build-python（上游强制同 minor 正是为此，绕过校验的代价） |
| 13 | 3.13 configure 不认 darwin 交叉（case 表无分支） | sed 补 `*-apple-darwin*` 分支（MACHDEP case + host_ident case，双处） |

## 死锁分析（当前卡点，证据链完整）

- lldb+debugserver 活体栈：`import_find_and_load → _imp_acquire_lock →
  _PyRecursiveMutex_Lock → PyMutex_Lock → _PyMutex_LockTimed →
  _PyParkingLot_Park → pthread_cond_wait（psynch_cvwait）永等`。
- 锁字节 0x03 = LOCKED|PARKED；`m->thread = 0`——**owner 从未记录**。
- 假设排除了：增量编译布局残留（全量重编复现）、hash 随机化/pycache
  （绕行复现）、stdlib 缺失（--version 走通）。
- **下一步选项**：a) debugserver watchpoint 抓 0x03 的写入者（spawn 模式
  不可行——interp 堆地址 ASLR；需 attach 后快设 watch，时序竞争）；
  b) **降级 CPython 3.12**（3.13 才引入 PyMutex/parking_lot 新锁系统，
  3.12 用老 pthread 锁——大概率绕开此死锁）；c) 逆向 3.13 lock.c 的
  fast-path/park 位语义与 iOS 10.3.3 psynch_cvwait 的交互。

## 布局（设备）

```
/var/mobile/tools/python3/bin/python3     主二进制（4.4MB，未 strip）
/var/mobile/tools/python3/lib/python3.13/        stdlib（Lib 内容）
/var/mobile/tools/python3/lib/python3.13/lib-dynload/  53 个扩展 .so
```

platform tag 显示 `macosx-.-arm`（configure 的 _PYTHON_HOST_PLATFORM
拼装丑但自洽，import 按文件 tag 匹配，功能无碍）。

---

## 重大发现：Apple armv7 8 字节原子操作有**对齐陷阱**（2026-11-16 攻克，11-16 晚**根因修正**）

> **⚠️ 本节结论于 2026-11-16 晚被实测修正。**
> 早期记录写的是"8 字节原子**静默失败**、写入成功但读回 0"——**那是错的**。
> 设备探针证明：非对齐的 8 字节原子**不是静默失败，而是直接 SIGBUS 硬崩**。
> 死锁只是同一约束在"不需要内存访问"的那条路径上呈现出的**另一种症状**。
> 保留下面的原始定位过程（有价值），但**根因以 §根因（修正版）为准**。

### 现象

CPython 3.13.18 设备上 `--version` 正常、`-c "pass"` **死锁**。
lldb+debugserver 活体栈：`import_find_and_load → _imp_acquire_lock →
_PyRecursiveMutex_Lock → PyMutex_Lock → park` 永等（单线程自己等自己）。

### 定位过程（trace 插桩逐层收窄）

1. `config_read` 全程 OK → 排除配置读取。
2. `_PyConfig_InitPathConfig`（含 `PyEval_EvalCode(getpath.py)`）OK。
3. 锁操作 trace 得到决定性证据：

```
[rm] lock m=... me=952905280 owner=0 bits=0 level=0
[rm]   acquired, storing owner
[rm]   &m->thread=0x...88 sizeof(ull)=8
[rm]   raw after store: 40 2e cc 38 00 00 00 00   ← 内存里写对了！
[rm]   owner stored = 0                            ← 但原子读回是 0
[rm] lock m=... me=952905280 owner=0 bits=1         ← 误判"非我持有"→ 再次 park
```

### 根因（修正版，2026-11-16 晚 · 设备探针实测）

```
sizeof(int64_t) = 8      _Alignof(int64_t) = 4      ← Apple armv7 ABI
&g_val = 0x72024         (mod 8 = 4)                ← 只有 4 字节对齐

__atomic_load_n(&g_val, __ATOMIC_RELAXED)
    →  Bus error: 10        ★ 直接 SIGBUS，进程当场死，连 printf 都打不完
```

**机制**：ARM 的 `ldrexd` / `strexd`（编译器给 8 字节原子用的独占访问指令）
**要求 8 字节对齐**；而 Apple 32 位 ARM ABI 给 `int64_t` 的**自然对齐只有 4 字节**。
clang 按 ABI 排布对象 → 生成非对齐的 `ldrexd` → **CPU 对齐异常 → SIGBUS**。

不是"数据读错"，是**硬件把进程打死**。这解释了所有诡异现象：

| 现象 | 解释 |
|---|---|
| `--version` 正常、`-c pass` 死锁 | 死锁路径的 8 字节原子**恰好落在 8 对齐地址**上（运气），于是"能跑但值不对"；换条路径就崩 |
| **SIGBUS 没有崩溃报告** | 崩在 dyld/早期，CrashReporter 来不及写盘（20 次崩溃 0 份报告） |
| 编译警告早就提示 | `-Watomic-alignment`：expected 8 bytes exceeds actual alignment 4 |

**设备探针完整结论**（`scratch-probe/atomic8*.c`）：

| 场景 | 结果 |
|---|---|
| 4 字节对齐 + 8 字节原子 | ❌ **SIGBUS** |
| 拆成两个 32 位原子读 | ✅ 数值正确 |
| 8 字节对齐 + 8 字节原子 | ✅ 数值正确 |

**`__attribute__((aligned(8)))` 加在字段上无效**——编译器按**类型**的自然对齐
判定，不是字段的声明对齐。（`offsetof` 验证 offset=8，但 `-Watomic-alignment`
仍报 4 字节。）真正的解法只有一个：**别让 8 字节原子碰 4 字节对齐的对象**。

### 修法（`Include/cpython/pyatomic_gcc.h`）

```c
#if defined(__APPLE__) && defined(__arm__) && !defined(__aarch64__)
    /* 8 字节原子在此平台不可靠：拆成两个 4 字节原子操作 */
    volatile uint32_t *p32 = (volatile uint32_t *)obj;
    __atomic_store_n(&p32[0], (uint32_t)(value & 0xffffffffu), __ATOMIC_RELAXED);
    __sync_synchronize();
    __atomic_store_n(&p32[1], (uint32_t)(value >> 32), __ATOMIC_RELAXED);
#else
    __atomic_store_n(obj, value, __ATOMIC_RELAXED);
#endif
```

`_Py_atomic_load_ullong_relaxed` 同法（两个 32 位读 + 屏障拼接）。
**设备探针实测**：4 字节原子 100% 可靠，8 字节不可靠（2026-11-16）。

### ⚠️ 当初只修了 1 个函数，漏了 18 个（2026-11-16 晚踩到）

第一次移植时**只改了 `_Py_atomic_load_ullong_relaxed` 一个**（因为死锁恰好撞上
它），`pyatomic_gcc.h` 里其余 **18 个 int64/uint64 入口**原封不动。后果：

```
$ python3 -c "import socket; socket.socket()"
Bus error: 10        ← 100% 复现，20/20
```

崩点：`init_sockobject()` 里的
`_Py_atomic_load_int64_relaxed(&state->defaulttimeout)`。

**修法**：`python3/patches/patch-atomic-armv7-align.py` 一次性覆盖
**5 个 load + 5 个 store**（seq_cst / relaxed / acquire / release），
文件顶部的 `SENTINEL` 保证幂等，3.13 与 3.14 通用（已在两个原始 tarball
上端到端验证）。

**未覆盖**：`add / exchange / compare_exchange / and / or` 这几个**读-改-写**
操作。拆半会破坏原子性，需要锁或 `ldrexd/strexd` 重试循环；实测路径未触发，
但**将来若出现新崩溃，优先查这几个**。

### 通用教训（已同步 `docs/toolchain.md` §19）

**Apple armv7 (armv7-apple-ios / armv7-apple-darwin) 上，任何 8 字节
`__atomic_*` 操作都不可信。** 移植遇到"写入成功但读回 0/垃圾"或
"单线程自己等自己"的死锁，优先怀疑 8 字节原子。判别方法：
- 编译期：看 `-Watomic-alignment` 警告
- 运行期：`__atomic_store_n` 后立即 `memcpy` 到字节数组打印（raw bytes 对
  但 `__atomic_load_n` 读回 0 = 确诊）

历史呼应：node 移植墙 #11（设备 `___atomic_load_8` 是 no-op，当时做
`c8fixed.o` 强制 `is_lock_free` 只认 ≤4 字节）——**同一根因的第二次现身**。

---

## 后两个大关的细节（2026-11-16）

### 关 2：Apple SystemLog 劫持 stdout

**症状**：`-c "print(42)"` 正常退出（EXIT=0）但**零输出**；
`os.write(1, b"...")` 却能输出。

**根因**：`Python/pylifecycle.c` 顶部按 `TARGET_OS_IPHONE` 自动
`#define USE_APPLE_SYSTEM_LOG 1`，于是 `init_apple_streams()` 用
`_apple_support.init_streams()` 把 `sys.stdout/sys.stderr` 换成
**SystemLog 对象**（走 os_log）。实测 `repr(sys.stdout)` =
`<SystemLog (level 0)>`。

**修法**：默认关闭，留 `-DPYTHON_IOS_USE_APPLE_SYSTEM_LOG=1` 逃生口：

```c
#  ifndef PYTHON_IOS_USE_APPLE_SYSTEM_LOG
#    define PYTHON_IOS_USE_APPLE_SYSTEM_LOG 0
#  endif
#  if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE && PYTHON_IOS_USE_APPLE_SYSTEM_LOG
#    define USE_APPLE_SYSTEM_LOG 1
#  else
#    define USE_APPLE_SYSTEM_LOG 0
#  endif
```

命令行 python3 必须写真实 fd，不能进系统日志。

### 关 3：cc-wrapper 给 Mach-O bundle 加 `-e _main`

**症状**：扩展 `.so` 全部 `dlopen` 失败：
`Symbol not found: _main ... Expected in: flat namespace`。

**根因**：CPython 的 `LDSHARED = $(CC) -bundle -undefined dynamic_lookup`，
而 `tools/cc-wrapper.sh` 无条件加 `-e _main`（为可执行文件设入口）。

**修法**：wrapper 识别 `-bundle`，此时不加 `-e _main`：

```sh
-bundle) LDARGS+=("-bundle"); IS_BUNDLE=1 ;;
...
ENTRY=(-e _main)
if [ "$IS_BUNDLE" = 1 ]; then ENTRY=(); fi
```

### 附带发现：扩展 .so 是符号链接

CPython 构建树里 `build/lib.*/xxx.so` 是指向 `../../Modules/xxx.so` 的
**符号链接**。打包必须 `tar -czhf`（`-h` 解引用）或 `cp -L`，否则设备上
得到一堆悬空链接 → `image not found`。

### 部署要点

扩展 `.so` 在设备上**必须 ldid 签名**才能被 `dlopen()` 接受
（与可执行文件同理）；`make-deb.sh` 已对每个 `.so` 执行 `ldid -S`，
`postinst` 再校验一遍。

---

## 后续修复（2026-11-16 续）：sqlite3 上线、ssl 部分可用

### ✅ sqlite3 3.54.1 完全可用

- 设备 `/usr/lib/libsqlite3.0.dylib` 是**悬空符号链接**，13 个 `_sqlite3_*` 符号
  全部被 dyld 拒绝（`tools/probe-symbols.sh` 实测）→ 不能链系统库。
- 改为静态链接 `~/ios-tool/sqlite-src/sqlite-autoconf-3540100/libsqlite3.a`
  （armv7，含 3.54.1 头文件），并把 `sqlite3_progress_handler` 补为 no-op
  stub（该库以 `SQLITE_OMIT_PROGRESS_CALLBACK` 编译）。
- 设备验收：`sqlite_version 3.54.1`、建表/插入/查询/计数全通。

### ✅ ssl：完全可用（TLS 1.3 实测通过）

**已解决**：
- `SSLv3_method` / `TLSv1_method` / `TLSv1_1_method` / `TLSv1_2_method`
  —— OpenSSL 4.0 已移除这些构造函数，CPython `_ssl.c` 仍取地址。用 stub
  返回 `TLS_method()`，`SSLv3_method` 返回 NULL（该协议已彻底移除）。
- `recvmmsg` —— 复用 `sysroot-overlay/usr/lib/libios-compat.a`（tor 时代产物）。
- `OPENSSL_armcap_P` —— no-asm 构建下 `OPENSSL_cpuid_setup` 是空函数
  （反汇编实证：push/mov/pop），符号在 dlopen 时找不到；在 `_ssl` 内定义它。
- **OpenSSL 归档里的 `atomic_alias.o` 是 ARM 模式绝对跳转**
  （`ldr pc, [pc, #-4]` + `.word`），在 Mach-O bundle 里触发
  "illegal text-relocation"。改用 **Thumb PIC 跳板**（`bl` 相对调用）后，
  `_ssl`/`_hashlib` 成功链接。
- `atomic_compat.c` 的 `my_atomic_*` 手写自旋锁崩溃 → 重写为
  **pthread mutex** 实现。

**最终根因（2026-11-16 攻克）**：`tools/` 里那对 `__atomic_*` 跳板
（`atomic_alias_pic.s`，从 node 时代继承）用 **`bl`** 跳转到 `my_atomic_*`。
`bl` 会覆盖 **LR**，被调函数 `bx lr` 后返回到跳板、LR 已损坏、参数寄存器也
被改写——实测表现为 `my_atomic_load(size=1, dest=NULL)` 并立即
SIGSEGV at 0x100。**改用尾调用 `b`** 后一切正常。

修好后实测：`ssl.SSLContext()` ✓、17 个 cipher、
**TLS 1.3 握手成功**（`TLS_AES_256_GCM_SHA384`）、
真实 HTTPS GET `example.com` 返回 `HTTP/1.1 200 OK`。

**根因方向**：libcrypto 以 `no-asm` 构建，`OPENSSL_armcap_P` 恒为 0
（`__ARM_MAX_ARCH__ < 7` 分支），OpenSSL 4.0 在某些分派点仍按该字索引函数表。

**为何重编带 asm 受阻**：ARM perlasm 产物用
`.word OPENSSL_armcap_P - .Llocal`（PIC 相对写法），clang 集成汇编器在
`-undefined dynamic_lookup` 链接模型下报 "symbol can not be undefined in a
subtraction expression"。需要非 PIC 形式的 perlasm 或双遍链接，留待后续。

### 结论

`_hashlib` 提供完整加密散列（14 种算法，SHA256/HMAC 验证通过），
`sqlite3` 提供数据库，**TLS 网络能力是唯一缺口**（需要 https 时暂用
宿主或系统工具）。

---

## 最终验收（2026-11-16 06:23 deb）

```
CPython 3.13.18 on darwin
math.pi      : 3.1415926536
zlib         : 17 bytes for 1000B
sha256       : 2cf24dba5fb0a30e26e83b2ac5b9e29e
hmac         : b60090e3052297aeb5a080889ce2fc4b
sqlite3      : 3.54.1        (建表/插入/查询 OK)
ssl          : OpenSSL 4.0.3 29 Sep 2026   (17 ciphers)
TLS          : TLSv1.3 TLS_AES_256_GCM_SHA384   ← 真实握手
HTTPS        : HTTP/1.1 200 OK                  ← 真实请求
ALL SYSTEMS GO
```

### OpenSSL 4.0.3 重编（带汇编，2026-11-16）

为解开 ssl 的死结，把 libcrypto 从 `no-asm` 改为**带汇编 + `__ARM_MAX_ARCH__=7`**
重编。perlasm 生成的 ARM 汇编用 `.word OPENSSL_armcap_P - .Llocal`（PIC 相对），
clang 集成汇编器在 `-undefined dynamic_lookup` 下拒绝
（"symbol can not be undefined in a subtraction expression"）；改成**绝对寻址**
后汇编可通过，但 bundle 又拒绝绝对 text-reloc。

**最终做法**：把 perlasm 里的 armcap 间接寻址整体替换成
`mov rX,#1`（常量 ARMV7_NEON）——A6X 确实支持 NEON，且这消除了全部
text-relocation。共改 8 个 `.pl`。同时：
- 关闭 `OPENSSL_NO_BN_ASM_GF2m`（并从归档移除该 asm 成员）
- `no-dso`（不建 provider 动态模块）
- `atomic_compat.c` 重写：**`is_lock_free` 必须返回 true**
  （`crypto/init.c:374` 以 `lock=NULL` 调用 `CRYPTO_atomic_load`，
  只有 lock-free 分支会填充结果；返回 false 会让 `tmp` 未初始化）
  且 8 字节原子拆成两个 32 位（设备 8 字节原子静默失败）
- **`atomic_alias_pic.s` 用 `b` 而非 `bl`**（本节顶部所述，关键 bug）

这些改动都在 `~/ios-tool/openssl-src/openssl-4.0.3/` 里，尚未回写到
`openssl/build.sh`（该脚本仍是 musl sysroot 时代的 no-asm 版本），
**下次重编 libcrypto 必须照此办理**——是 TODO。

---

# CPython 3.14.10 移植（2026-11-16，同日完成）

**结论：3.13 趟出来的路让 3.14 一次到位。** 设备验收全通，
含 TLS 1.3 真实握手与 HTTPS 请求。

## 复用与差异

| 项目 | 3.13.18 | 3.14.10 |
|---|---|---|
| 8 字节原子拆半 | 手工改 | **补丁脚本一键**（同一处 `pyatomic_gcc.h`） |
| Apple SystemLog | `pylifecycle.c` 的 `USE_APPLE_SYSTEM_LOG` | **重构成 `initconfig.c` 的 `USE_SYSTEM_LOGGER_DEFAULT`**（有运行时 `-X use_system_logger` 开关，更干净） |
| 64 位字段对齐 | 手工 | 补丁脚本（3.13 阶段已同步，3.14 unchanged） |
| configure darwin 分支 | sed 两处 | **同样两处**（`*-apple-darwin*` 仍未进上游 case 表） |
| build-python | 需自编宿主 3.13 | 宿主 `/usr/bin/python3.14` 直接满足 |
| `_ssl` 符号冲突 | — | **新增**：asm 版 libcrypto 自带 `OPENSSL_armcap_P`，stub 里不能再定义 |

## 设备验收（全新 deb 安装，mobile 身份）

```
Python  : 3.14.10
math.pi : 3.14159265
zlib    : 17 bytes / 1000B
sha256  : 8f434346648f6b96df89
sqlite  : 3.54.1        (建表/插入/查询)
ssl     : OpenSSL 4.0.3
TLS     : TLSv1.3 | TLS_AES_256_GCM_SHA384   ← 真实握手
HTTPS   : HTTP/1.1 200 OK                    ← 真实请求
53 个扩展全部 ldid 签名并导入成功
```

## 包

- `python314_3.14.10-1_iphoneos-arm.deb`（19MB，仓库第 28 包）
- 装到 `/var/mobile/tools/python314`，与 3.13 **共存**
- `/var/mobile/tools/bin/python3.14` 符号链接
- **注意**：configure 时的 prefix 是 `/var/mobile/tools/python3`，
  与 3.14 的安装路径不同，运行需 `PYTHONHOME=/var/mobile/tools/python314`
  （若要免除，重编时传 `--prefix=/var/mobile/tools/python314`）

## 复用清单（下次移植新版 CPython）

**两个补丁脚本，都要跑**（顺序无所谓，互不重叠）：

1. `python3/patches/patch-atomic-armv7-align.py \
       <srcdir>/Include/cpython/pyatomic_gcc.h`
   —— 8 字节原子拆半。**漏了它必 SIGBUS**（socket/锁/超时全崩）。
   幂等；3.13/3.14 通用；已对两个原始 tarball 端到端验证过。
2. `python3/patches/patch-cpython-ios-armv7.py <srcdir>`
   —— 关 Apple SystemLog、64 位字段对齐等。
3. `configure` / `configure.ac` 各补 `*-apple-darwin*` 分支（两处 case）
4. `PYTHON_SRC=<srcdir> BUILD_PYTHON=<同 minor 宿主> ./python3/build.sh`
   - 注意 `obj/` 是**单一目录**，3.13 与 3.14 共用；交替构建会互相覆盖。
     给并存的版本用独立构建树（本项目 3.13 在 `~/scratch/python3/obj313`），
     打包时用 `PYTHON_OBJ=<tree> ./python3/make-deb.sh` 指定。
   - `build.sh` 生成的两个 stub（`ssl_compat_stub.o`、`sq_progress_stub.o`）
     是**手工构建树时最容易漏的两步**，漏了 `_ssl` 链接报
     `ld: file not found: ssl_compat_stub.o`。
5. 扩展在构建树里是符号链接 → 打包用 `tar -h` / `cp -L`
6. 设备上二进制与每个 `.so` 都要 `ldid -S`

### 只改一个模块时的快路径

`_socket` 这类单模块修复**不必全量重编**：

```sh
python3 <srcdir>/configure ...        # 建独立构建树（一次）
make Modules/_socket$(EXT_SUFFIX)     # 只编这一个
# 部署：su root 覆盖设备上的 .so + chmod 755 + chown mobile:mobile + ldid -S
```

实测有效：只替换 `_socket.so` 一个文件，socket/TLS 全部恢复，
其余 52 个模块无需重编。
