# python3 移植补丁与流程（iOS 10 / armv7）

两条流水线共用 `../build.sh`，靠 `PYTHON_SRC` + `BUILD_PYTHON` 切换版本：

```sh
# 3.13.18（宿主自带 3.13 build-python 需自行编，见 docs/python3.md）
IOS_LD64=... PYTHON_SRC=~/scratch/python3/src313 \
  BUILD_PYTHON=~/scratch/python3/hostbuild/python ./build.sh

# 3.14.x（宿主 /usr/bin/python3.14 正好同 minor）
IOS_LD64=... PYTHON_SRC=~/scratch/python3/src \
  BUILD_PYTHON=/usr/bin/python3.14 ./build.sh
```

## 源码补丁

`patch-cpython-ios-armv7.py <srcdir>` —— 一键应用全部 iOS/armv7 修正：

1. **8 字节原子拆半**（`Include/cpython/pyatomic_gcc.h`）
   Apple armv7 ABI 给 `unsigned long long` 4 字节对齐，8 字节
   `__atomic_*` 静默失败（写进去读回垃圾）→ 递归锁自我死锁。
2. **关闭 Apple SystemLog**（`Python/pylifecycle.c`，3.13；
   3.14 是 `Python/initconfig.c` 的 `USE_SYSTEM_LOGGER_DEFAULT`）
   iOS 默认把 `sys.stdout/stderr` 换成 os_log 对象，CLI 下 `print` 无输出。
3. **64 位字段对齐标注**（`pycore_interp_structs.h` / `pycore_typeobject.h` /
   `pycore_interp.h` / `pycore_lock.h`）

## configure 补丁（3.13 与 3.14 均需要）

`configure` / `configure.ac` 的 host case 表缺 `*-apple-darwin*` 分支，
要各补一处（MACHDEP case 与 host_ident case），否则报
"cross build not supported"。另有 build-python 版本校验（3.14 用宿主
3.14 即天然满足；3.13 需放开或自编宿主 3.13）。

## 已知的通用坑（详见 docs/python3.md）

- `#ifdef HAVE_X` 语义下 `#define X 0` 无效，须用 autoconf undef 形态
- Makefile 有 `pyconfig.h: config.status` 依赖，压制必须在 configure 参数级
- `AC_CHECK_LIB([rt], ...)` 嵌套回退要连 `ac_cv_lib_rt_*` 一起压
- libmpdec 的 UNIVERSAL 架构表无 arm32，需 make 行覆盖 `-DCONFIG_32=1 -DANSI=1`
- 扩展 `.so` 在构建树里是符号链接，打包须 `tar -h` / `cp -L`，且设备上要 `ldid -S`
- cc-wrapper 对 `-bundle` 不能加 `-e _main`
