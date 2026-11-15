# python3 移植（CPython 3.13.18 / armv7 iOS 10.3.3）——进行中

> 2026-11-15 立项当日战报。SDK sysroot 模式（AGENTS 规则 5）。
> 源码 `~/scratch/python3/src313`（3.13.18）；宿主 build-python
> `~/scratch/python3/hostbuild/python`（3.13.18 原生，frozen 生成器必需）。

## 当前状态

- **构建全链打通**：configure → make → 链接 → 审计 336/336 符号全过 →
  设备 `--version` 跑通（`Python 3.13.18`）。
- **卡点**：`-c`/import 期死锁——`_imp_acquire_lock` 的递归锁
  （`_PyRecursiveMutex`）上 `PyMutex_Lock` 永久 park，锁字节 = 0x03
  （LOCKED|PARKED），`m->thread = 0`（owner 未记录）。lldb+debugserver
  活体栈已抓（`import_find_and_load → _imp_acquire_lock → 死`）。

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
