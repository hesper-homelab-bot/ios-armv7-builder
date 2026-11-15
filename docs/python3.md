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

## 重大发现：Apple armv7 8 字节原子操作静默失败（2026-11-16 攻克）

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

### 根因（编译警告早就说了）

```
warning: misaligned atomic operation may incur significant performance penalty;
         the expected alignment (8 bytes) exceeds the actual alignment (4 bytes)
```

**clang 在 Apple armv7 目标上强制 `unsigned long long` 为 4 字节对齐**
（Apple ABI 历史怪癖；Linux armv7 是 8）。因此：
- `__atomic_store_n(u64*)` 编译成 `strexd`（独占存储），在 **4 对齐的运行时地址**上
  **静默失败**（不报错、不崩溃，就是没写进去）
- `__atomic_load_n(u64*)` 同样不可靠

**`__attribute__((aligned(8)))` 加在字段上无效**——编译器生成原子操作时用的是
**类型的自然对齐**，不是字段的声明对齐。（`offsetof` 验证 offset=8，但
`-Watomic-alignment` 仍报 4 字节，即编译器按类型判定。）

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
