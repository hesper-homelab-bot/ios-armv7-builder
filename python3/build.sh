#!/bin/bash
# Build CPython 3.14.10 for armv7 iOS 10.3.3 (iPad4/A6X).
#
# 立项（用户 2026-11-15"python3.开工"）：SDK sysroot 模式（AGENTS 规则 5）。
# 依赖全部现成：openssl 4.0.3 静态库、zlib 1.3.1 静态库、设备
# libncursesw.5.dylib；宿主 python3.14.4 与目标同 minor（--with-build-python
# 直接命中，构建期生成器用它跑）。
#
# CPython 交叉编译要点（3.14）：
#   * --build/--host 分离 + --with-build-python=<同 minor 宿主 python>
#   * ac_cv_file__dev_ptmx/ptc 手工给定（交叉下 configure 无法探测）
#   * 可选扩展模块交叉时默认禁用，用 py_cv_module_<name>=enabled 逐个
#     显式开启并给链接参数（第一轮先过核心，ssl/zlib 第二轮上）
#   * 静态构建（--disable-shared）：python3 CLI 自含，扩展模块静态链入
# Source: https://www.python.org/ftp/python/3.14.10/Python-3.14.10.tar.xz
#
# Usage: IOS_LD64=... ./build.sh    # out-of-tree build in obj/
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
PYSRC="${PYTHON_SRC:-$HOME/scratch/python3/src}"
SDK="${IOS_SDK:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
OSSL="${OSSL_PREFIX:-$HOME/ios-tool/openssl-src/openssl-4.0.3}"
ZLIB_STATIC="${ZLIB_STATIC:-$HOME/ios-tool/build-ios/install/lib/libz.a}"
# sqlite3: the device's /usr/lib/libsqlite3.0.dylib is a dangling symlink and
# provides none of the symbols (_sqlite3_* all rejected by dyld -- verified
# 2026-11-16 with tools/probe-symbols.sh).  Link the static lib built for this
# device instead, and use its own headers (3.54.1) rather than the SDK's 3.16.0
# so header and library agree.
SQLITE_PREFIX="${SQLITE_PREFIX:-$HOME/ios-tool/sqlite-src/sqlite-autoconf-3540100}"
COMPAT_STATIC="$root/sysroot-overlay/usr/lib/libios-compat.a"
BUILDPY="${BUILD_PYTHON:-/usr/bin/python3.14}"
# Install prefix baked into the interpreter's default sys.path search.
# 3.13 and 3.14 coexist on the device under different directories, so this
# must be overridable -- if the baked prefix does not match where the deb
# actually installs, the interpreter cannot find its stdlib without an
# explicit PYTHONHOME.  Package with PYTHON_PREFIX=/var/mobile/tools/python314
# to match make-deb-314.sh.
PYTHON_PREFIX="${PYTHON_PREFIX:-/var/mobile/tools/python3}"

[ -f "$PYSRC/configure" ] || {
	echo "missing $PYSRC/configure -- fetch Python-3.14.10.tar.xz from" >&2
	echo "  python.org/ftp/python/3.14.10/ and extract to src/" >&2
	echo "  sources.lock row 'python3' -- verify/fetch with:" >&2
	echo "    $root/tools/fetch-src.sh --lock python3" >&2
	exit 1
}
[ -x "$BUILDPY" ] || { echo "missing host $BUILDPY (need 3.14 for build-python)" >&2; exit 1; }
[ -f "$SDK/usr/include/uuid/uuid.h" ] || { echo "missing SDK under $SDK" >&2; exit 1; }
[ -f "$ZLIB_STATIC" ] || { echo "missing $ZLIB_STATIC" >&2; exit 1; }
[ -f "$SQLITE_PREFIX/libsqlite3.a" ] || { echo "missing $SQLITE_PREFIX/libsqlite3.a" >&2; exit 1; }
[ -f "$COMPAT_STATIC" ] || { echo "missing $COMPAT_STATIC" >&2; exit 1; }

export IOS_SYSROOT="${IOS_SYSROOT:-$SDK}"
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set IOS_LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

PY_SUPPRESS_FUNCS="clock_settime accept4 bind_textdomain_codeset clock_nanosleep clock_settime closefrom close_range copy_file_range dladdr1 explicit_bzero explicit_memset fdwalk fexecve fork1 fseek64 ftell64 futimens futimesat gethostbyname_r getresgid getresuid getspent getspnam memrchr mkfifoat mknodat memremap plock posix_fadvise posix_fallocate posix_spawn_file_actions_addclosefrom_np preadv preadv2 pwritev pwritev2 process_vm_readv pthread_condattr_setclock pthread_getattr_np pthread_getcpuclockid pthread_set_name_np ptsname_r rtpSpawn sched_get_priority_max sched_rr_get_interval sched_setaffinity sched_setparam sched_setscheduler sem_clockwait sem_timedwait setns setresgid setresuid sigtimedwait sigwait splice unshare sigwaitinfo mremap tmpnam_r _getpty utimensat"

CC="$root/tools/cc-wrapper.sh"
AR="$root/tools/darwin-ar"
RANLIB="$root/tools/darwin-ranlib"

build="$here/obj"
rm -rf "$build"
mkdir -p "$build" "$root/out"
cd "$build"

# iOS 10.1+ 的 getentropy 在设备 libSystem 里（sdk-libsystem_kernel.tbd
# 有 _getentropy），但 10.3 SDK 没有 sys/random.h——纯缺声明。
# 垫片头全局 -include（只加声明，无害）。
cat > pygetentropy_shim.h <<'EOF'
#ifndef PY_IOS_SHIM_H
#define PY_IOS_SHIM_H
#include <stddef.h>
#include <sys/types.h>
extern int getentropy(void *, size_t);
/* iOS 10.3 SDK hides sendfile(2) behind !defined(_POSIX_C_SOURCE)
   (sys/socket.h:665) -- CPython's pyconfig.h defines _POSIX_C_SOURCE, so
   socket.h only forward-declares struct sf_hdtr.  The function exists in
   libSystem (_sendfile in sdk-libsystem_kernel.tbd) -- re-declare fully.
   Shim is -include'd before everything, so this complete definition comes
   first and socket.h's later forward declaration is a legal redeclaration. */
struct iovec;
struct sf_hdtr {
	struct iovec *headers;
	int hdr_cnt;
	struct iovec *trailers;
	int trl_cnt;
};
int sendfile(int, int, off_t, off_t *, struct sf_hdtr *, int);
#endif /* PY_IOS_SHIM_H */
EOF
CPPFLAGS="-include $build/pygetentropy_shim.h -I$SQLITE_PREFIX"
LDFLAGS="-L$SQLITE_PREFIX"
export CPPFLAGS LDFLAGS

CC="$CC" \
AR="$AR" RANLIB="$RANLIB" READELF=llvm-readelf-21 \
"$PYSRC/configure" \
	--build=x86_64-pc-linux-gnu \
	--host=armv7-apple-darwin \
	--with-build-python="$BUILDPY" \
	--with-openssl="$OSSL" \
	--disable-shared \
	--disable-test-modules \
	--prefix="$PYTHON_PREFIX" \
	CPPFLAGS="-include $build/pygetentropy_shim.h -I$SQLITE_PREFIX" \
	LIBS="$SQLITE_PREFIX/libsqlite3.a" \
	ac_cv_file__dev_ptmx=yes \
	ac_cv_file__dev_ptc=no \
	ac_cv_buggy_getaddrinfo=no \
	$(for sym in $PY_SUPPRESS_FUNCS; do echo "ac_cv_func_$sym=no"; done) \
	ac_cv_lib_rt_clock_nanosleep=no \
	ac_cv_lib_rt_clock_settime=no \
	ac_cv_header_sqlite3_h=yes \
	$(for fn in sqlite3_open sqlite3_bind_double sqlite3_column_decltype \
	           sqlite3_column_double sqlite3_complete sqlite3_progress_handler \
	           sqlite3_result_double sqlite3_set_authorizer sqlite3_trace_v2 \
	           sqlite3_trace sqlite3_value_double sqlite3_load_extension \
	           sqlite3_serialize sqlite3_close; do
	      echo "ac_cv_lib_sqlite3_$fn=yes"
	  done) \
	py_cv_module__lzma=n/a \
	py_cv_module__bz2=n/a \
	py_cv_module__dbm=n/a \
	py_cv_module_nis=n/a \
	py_cv_module_readline=n/a \
	py_cv_module__scproxy=n/a \
	py_cv_module__curses=n/a \
	py_cv_module__curses_panel=n/a \
	py_cv_module__ctypes=n/a \
	py_cv_module__ctypes_test=n/a

# ---- AC_CHECK_FUNCS 恒真探针假阳压制（2026-11-15 审计）----
# 链接型函数探测在 dynamic_lookup 下恒真，iOS 10.3.3 libc 实际没有的函数
# 被误开 HAVE_*=1。清单来源：pyconfig.h 全部 enabled HAVE_* 对设备 tbd
# 符号集（518 个 tbd / 19 万符号）做差集 + 人工过筛（剔除头文件/类型/
# 结构字段类非函数宏——那些是编译型探测的真结果）。与 node/ffmpeg 时代的
# iOS 10 压制清单高度重合（accept4/utimensat/pthread_condattr_setclock/
# gethostbyname_r 均为老面孔）。
#
# **两个坑（2026-11-15 都踩过）**：
# ① `#ifdef HAVE_X` 语义下 `#define X 0` 无效，必须 undef——所以不能
#    只在 pyconfig.h 上 sed 置 0；
# ② Makefile 有 `pyconfig.h: config.status` 依赖，make 阶段 config.status
#    重跑会按原始探测值**重新生成 pyconfig.h**，configure 后 sed 的修改
#    被洗掉（首轮实录）。正解 = configure 参数级
#    `ac_cv_func_<name>=no`，config.status 生成时即写 undef。
# ③ 嵌套回退探测（2026-11-15 三轮实录）：clock_nanosleep 是
#    AC_CHECK_FUNCS 失败后 AC_CHECK_LIB([rt],...) 回退——压 func 缓存不够，
#    还要压 `ac_cv_lib_rt_clock_nanosleep=no`，否则 -lrt 回退在
#    dynamic_lookup 下恒真，AC_DEFINE 强行写入。同类回退出现时照此办理。
# ④ iOS 特判失守（2026-11-15）：上游对 clock_settime 有
#    `ac_sys_system != "iOS"` 守护（iOS 上链接可得但用即崩，configure.ac
#    5726 注释明言），我们 host=armv7-apple-darwin 绕 framework 强制时
#    ac_sys_system=Darwin，特判失守——以 ac_cv_func + ac_cv_lib 双压
#    等效达成上游意图。


echo "configure OK"
# libmpdec 机器形态：configure 对 Darwin* 一律传 -DUNIVERSAL=1，而
# mpdecimal.h 的 UNIVERSAL 架构表只认 ppc/i386/x86_64/arm64——armv7 撞
# #error "unknown architecture"，CONFIG_32 从未定义（2026-11-15 实录）。
# 命令行覆盖为显式 32 位 ANSI 配置。
MPDEC_CFLAGS="-I$PYSRC/Modules/_decimal/libmpdec -DCONFIG_32=1 -DANSI=1"

# sqlite3_progress_handler stub: our static libsqlite3.a was built with
# SQLITE_OMIT_PROGRESS_CALLBACK, but _sqlite3 requires the symbol at link
# time (and -undefined dynamic_lookup would otherwise leave it dangling,
# failing only at dlopen on the device).  (2026-11-16)
# --- ssl compatibility stubs (merged into a single object) ---------------
# (a) OpenSSL 4.0 removed SSLv3 and the TLSv1/TLSv1.1/TLSv1.2 method
#     constructors, but CPython's _ssl.c still takes their addresses; return
#     TLS_method() so legacy PROTOCOL_* constants behave like PROTOCOL_TLS.
# (b) OPENSSL_armcap_P: our libcrypto.a is built with `no-asm`, which makes
#     OPENSSL_cpuid_setup() an empty function and leaves the capability word
#     undefined at dlopen time ("Symbol not found: _OPENSSL_armcap_P").
#     Defining it here satisfies the reference.
#
# KNOWN LIMITATION (2026-11-16): even with the capability word set,
# ssl.SSLContext() still crashes (PC=0x100 inside OPENSSL_init_crypto).
# `import ssl` and ssl.OPENSSL_VERSION work.  Fixing this needs libcrypto
# rebuilt WITH assembly, which is currently blocked: the ARM perlasm output
# uses `.word OPENSSL_armcap_P - .Llocal` (PIC style) that clang's integrated
# assembler rejects under our -undefined dynamic_lookup link model.
cat > ssl_compat_stub.c <<'EOF'
typedef struct ssl_method_st SSL_METHOD;
extern const SSL_METHOD *TLS_method(void);
const SSL_METHOD *TLSv1_method(void)   { return TLS_method(); }
const SSL_METHOD *TLSv1_1_method(void) { return TLS_method(); }
const SSL_METHOD *TLSv1_2_method(void) { return TLS_method(); }
const SSL_METHOD *SSLv3_method(void)   { return 0; }
/* NOTE: OPENSSL_armcap_P is *not* defined here.  Since libcrypto was rebuilt
   with assembly enabled (-D__ARM_MAX_ARCH__=7), crypto/armcap.c provides a
   real OPENSSL_cpuid_setup and the symbol itself; defining it here would be a
   duplicate symbol.  It was only needed for the old no-asm build. */
EOF
"$CC" -c -o ssl_compat_stub.o ssl_compat_stub.c

cat > sq_progress_stub.c <<'EOF'
struct sqlite3;
typedef int (*sqlite3_progress_handler_fn)(void *);
void sqlite3_progress_handler(struct sqlite3 *db, int n,
                              sqlite3_progress_handler_fn handler, void *arg)
{ (void)db; (void)n; (void)handler; (void)arg; }
EOF
"$CC" -c -o sq_progress_stub.o sq_progress_stub.c

# Static libs must be named explicitly on the module link lines -- configure's
# LIBS=/LDFLAGS= only affect its own probes, not the per-module link commands
# (verified 2026-11-16: -lsqlite3 / -lssl left every symbol undefined).
OSSL_LIB="$OSSL/lib"
SQLITE_LIB="$SQLITE_PREFIX/libsqlite3.a"

make -j"$(nproc)" \
	MODULE__DECIMAL_CFLAGS="$MPDEC_CFLAGS" \
	LIBMPDEC_CFLAGS="$MPDEC_CFLAGS \$(PY_STDMODULE_CFLAGS) \$(CCSHARED)" \
	MODULE__SQLITE3_LDFLAGS="$SQLITE_LIB sq_progress_stub.o" \
	MODULE__SSL_LDFLAGS="$OSSL/atomic_alias_pic.o $OSSL/atomic_compat.o -L$OSSL_LIB $OSSL_LIB/libssl.a $OSSL_LIB/libcrypto.a ssl_compat_stub.o $COMPAT_STATIC" \
	MODULE__HASHLIB_LDFLAGS="$OSSL_LIB/libcrypto.a"

echo "== built =="
ls -l "$build/python"
