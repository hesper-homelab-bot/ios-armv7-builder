# 交叉编译工具链通用规则（iPad4 / armv7 / iOS 10.3.3）

> 适用范围：所有为这台设备交叉编译的软件（node、quickjs、dropbear、openssh、
> openssl、curl…）。软件专项细节见同目录各 md；本文只写**工具链层面可复用的规则**。
> 维护：大肥鱼。正本在本 git 仓库 `docs/`；`~/.dsh/AGENTS.md` 是它的符号链接入口。

## 1. 构建环境（每次都要 export）

```sh
export IOS_SYSROOT=$HOME/ios-armv7-builder/tmp/sysroot
export IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
```

- C 驱动：`~/ios-armv7-builder/tools/cc-wrapper.sh`
- C++ 驱动：`~/ios-tool/cxx-wrapper.sh`（内部转调 cc-wrapper，附加
  `-nostdinc++ -isystem libcxx15-headers` 与 `_LIBCPP_NO_EXCEPTIONS`/
  `_LIBCPP_DISABLE_AVAILABILITY`，为匹配设备上的 libc++ 6.0.1 ABI）
- **cxx-wrapper 按自身 cwd 解析相对输入路径 → 传给它的文件路径一律绝对路径**，
  否则 `ld: file not found`。
- 常见手误：`LD64=IOS_LD64=...` 会把值设成字面量；变量名是 **`IOS_LD64`**。

## 2. 归档规则（ld64 的坑）

- **ld64 静默忽略 GNU thin archive**（不报错，符号就是缺）→ 所有 `.a`
  必须转成 darwin 扁平归档：`llvm-ar-21 --format=darwin`。
- `--format=darwin` 只存 basename → 同名成员互相覆盖（多个 heap.o/factory.o）
  → 成员名按路径哈希唯一化。
- **转换后必须验证成员数**（曾出现"成功"但 0 成员，ar 跑错了 cwd）。
- **对象 vs 归档的优先级**：普通 `.o` 对象永远压过归档成员；归档成员只在
  符号仍未定义时才被拉入。**放一个同名桩对象在链接行前面，会静默遮蔽
  归档里的真身**（node 快照桩事故的根源）。排查符号"明明在归档里却没生效"
  时先查这个。

## 3. thumb / ARM 规则（armv7）

- 汇编实现函数（`.S`）必须显式 `.thumb_func`，并尽量 `-mthumb -march=armv7` 汇编。
- 链接器警告 `ARM function not 4-byte aligned: <name>` = 该符号没有 thumb 位，
  thumb 调用方经 veneer 进入会 SIGILL——**不要忽略**。
- 汇编完必须验证：`llvm-objdump-21 -d --triple=thumbv7-apple-ios`，
  `bx lr` 应为 `4770`；`llvm-nm-21` 显示 `T`/`t`（thumb 位已置）。
- C 源码**无法**定义 `__atomic_is_lock_free` 等 clang builtin
  （`definition of builtin function`；`-fno-builtin` 也无效）→ 用 `.S`。

## 4. 原子操作雷区（设备级）

- 设备的出线原子 libcall **`___atomic_load_8` 是空函数**（64 位原子读静默
  返回垃圾；store 正常）。64 位 `std::atomic` 在 node/V8/libc++ 里都会中招。
- 修法：自备 armv7 原子 shim（LDREXD/STREXD + `dmb ish`），并让
  `__atomic_is_lock_free` 对 armv7 只认 `size <= 4`（8 字节走带锁路径）。
- **`___atomic_is_lock_free` 谓词本身在设备 libSystem 里没有导出**——
  `___atomic_load`/`___atomic_store`/`___atomic_compare_exchange` 三个
  操作符都在，唯独谓词不在。clang 新版会为 OpenSSL 4 这类库生成该
  libcall：链接"成功"（flat namespace 兜底），设备端一进
  `CRYPTO_atomic_*` 就被 dyld 杀（`_setproctitle` 同款死法）。
  修法：链 `tools/shims/c8fixed.S`（2026-11-19 从 node/patches/shims/
  提升为公共垫片，node/nginx/mosh 共用）——≤4 且指针对齐 → 1，否则 0。
- **静态库会带着这个引用漂移**：openssl-4.0.3 于 2026-11-16 重建后，
  threads_pthread.o 开始引用 `___atomic_is_lock_free`；此前链接干净的
  nginx 1.26.3 换 1.31.9 重链即中招（nginx 墙#7）。教训：每个新链接的
  二进制都要跑 `tools/check-undefined.sh`，不要引用"上次没有这个符号"
  的历史结论。
- 症状特征：插入成功、紧跟的查找失败；成功/失败集合随构建漂移（栈垃圾决定）。

## 5. 部署与验证

- 部署三件套（缺一 exec 即 SIGKILL）：`chmod 755 X && chown mobile:mobile X && ldid -S X`
- 排查 SIGKILL 第一步：设备上 `ldid -e X`——有输出=已签名；
  `_assert(signature != NULL)`=未签名。
- 就地覆盖已存在文件有 vnode 风险 → **部署成新文件名，再 `rm -f` 旧名 + `cp`**。
- **覆盖已签名二进制（2026-11-19 curl 实锤）**：`cp` 原地覆盖已签名文件后，
  即使新内容自带有效签名、md5 与源一致，内核仍拒载（依赖 inode 状态；
  设备实测三连 Killed:9 无崩溃报告）。**覆盖后必须对目标重新 `ldid -S`**
  （重写签名即复活）；正规部署走 deb——dpkg 解包 = 新 inode + rename +
  postinst 重签，天然免疫。
- 崩溃报告：`/var/mobile/Library/Logs/CrashReporter/*.ips`（SIGKILL 无报告；
  连续崩溃会被限流）。
- **.ips 符号化**：报告里 `0xADDR base + off` 的 base 是设备加载基址；
  主机地址 = `host_TEXT_vmaddr(0x4000) + (dev - base)`。必须用**同字节**
  的未 strip 孪生体（`llvm-nm -n` + 二分，或 llvm-symbolizer-21 --obj）；
  跨构建符号化漂移 KB 级，不可用。
- 探针模板（构建+部署+跑）：

```sh
export IOS_SYSROOT=$HOME/ios-armv7-builder/tmp/sysroot IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
~/ios-armv7-builder/tools/cc-wrapper.sh -O1 -o /tmp/probe /tmp/probe.c [额外 .o/.a]
scp /tmp/probe mobile@<device>:/var/mobile/scratch/probe.new
ssh mobile@<device> 'cd /var/mobile/scratch && rm -f probe && cp probe.new probe && \
  chmod 755 probe && chown mobile:mobile probe && ldid -S probe && ./probe'

> **默认以 mobile 会话验证**（与用户日常身份一致；root 能绕过的权限坑
> 全被掩盖，/dev/bpf* 事件是教训）。需要 root 的操作（dpkg -i、chmod 设备
> 节点）显式切 root 并在汇报中注明。
```

## 6. 设备连接

- 具体地址/别名只在 **DEVICE.md（gitignored，私有）** 与 `~/.ssh/config` 里，
  本仓库文档一律用 `<device>` 占位。
- **port 22 = 自编 dropbear（唯一 sshd），现代算法直连，无需兼容参数**。
- host key 变更后先 `ssh-keygen -R <device>` 再连。
- 守护：`/var/mobile/.local/bin/ssh-selfheal.sh`（每 120s；详见 docs/dropbear.md）。

## 7. 设备内存/执行模型（探针实测，写死的事实）

| 行为 | 结果 |
|---|---|
| 出生即 RWX 的 mmap | ✅ 可用 |
| mprotect 转 RWX 后执行 | ❌ SIGBUS |
| MAP_JIT | ❌ EINVAL |
| 带 platform-application entitlements 的二进制 | ❌ exec 即杀（别指望提权解锁） |
| V8 `kMmapFd = VM_MAKE_TAG(255)` | ❌ SIGSYS（已补丁为 -1，匿名映射） |

| 信号 | 含义 |
|---|---|
| SIGKILL(9)/137，无崩溃报告 | exec 层签名拒绝（先查 ldid）或 jetsam |
| SIGSYS | 内核拒绝系统调用（如 Linux cacheflush） |
| SIGSEGV @ 小地址 | 空指针/未初始化表 |
| SIGILL | thumb 位缺失或栈耗尽后的野跳 |


## sysroot 结构体的运行时 ABI（wall #14 教训，2026-11-11）

编译期能过 != 运行时 ABI 正确。sysroot 是手搓的：每个**与内核交互的
结构体**（ioctl/kevent/socket option/……）都要用**多元素探针**在设备上
验证，而不是只看编译+单元素调用。已有先例：

- `sys/event.h` struct kevent 曾带 `uint64_t ext[4]`（52B 步长），
  iOS 10.3.3 armv7 内核实际按 20B 无 ext 读——libuv/ares 的 changelist
  在第 2+ 个 change 起全错（坏 fd、EINVAL abort、SIGBUS）。
  已删 ext 并留注释（sizeof 必须 =20）。

规则：新增/修改 sysroot 头里与 syscall 相关的结构体时，
编译一个多元素探针（≥2 个元素走完整 syscall 路径）在设备上跑通
才算数。单元素探针测不出 stride 错位（第 1 个永远对齐）。

## 8. sysroot 头的"Linux 值穿马甲"雷区（nmap 移植 2026-11-12）

musl 头里凡是**数值常量**（ioctl request、netdb 的 NI_/AI_/EAI_、协议号）
都默认是 **Linux/glibc 值**，与 Darwin ABI 经常不同，且差异是静默的：

- `bits/ioctl.h` 的 `_IOW` 系宏是 Linux 编码 → 所有"用宏构造"的 BSD ioctl
  （BIOCSETIF、SIOCAIFADDR…）拿到垃圾 request code，值还随 include 顺序漂移
  （先 include ioccom.h 就对，后 include 就错——两次编译结果不同的怪象之源）。
  已改为直接 include `sys/ioccom.h`（BSD 语义）+ Darwin tty 值无条件覆盖。
- `netdb.h` 的 `NI_NUMERICHOST` Linux=1 / Darwin=2：传 1 时设备返回的是
  **主机名**（Darwin 的 1 是 NI_NOFQDN），不是错误，更阴险。EAI_* 符号也
  全不同（Darwin EAI_NONAME=8，musl=-2）。已按 Apple Libinfo 正本重写。
- 判据固化：**两次探针结果不同 → 先怀疑宏依赖 include 顺序**；打印宏的
  数值（`printf("%lx", (unsigned long)BIOCSETIF)`）比猜测快十倍。

另外：cc-wrapper 现在对 `-M/-MM/-MD/-MMD` 直接透传 clang。此前的行为
（当作普通 flag 走编译+链接）会让 clang 把**依赖清单写进 .o**（ASCII
毒化），nsock 的 makefile.dep 规则是第一个受害者。排查手段：`file *.o`
看见 "ASCII text" 即中毒，删掉重编。

## 9. autoconf 交叉编译探测的三类骗局（nginx/mosh 2026-11-13）

autoconf 的探针在交叉编译下**全都不可信**，且失败形态各不相同。三个实例，
按"信号 → 根因 → 修法"记：

### 9.1 只编译不链接：声明存在 = 探针通过

`auto/unix` 的 `ngx_feature_run=no` 让 setproctitle() 探针**只编译**测试程序。
sysroot-overlay 的 `unistd.h` 里有一行 `void setproctitle(const char*, ...);`
（为别的包准备的），于是 `NGX_HAVE_SETPROCTITLE=1` 被误置。
ngx_setproctitle.h 随即把 `ngx_setproctitle()` 映射到 libc 符号——而
**iOS libSystem 根本不导出它**（实测：`nm -g /usr/lib/libSystem.B.dylib |
grep setproctitle` 为空）。链接居然成功（flat namespace 留下 undefined），
错误推迟到运行期：

```
dyld: Symbol not found: _setproctitle
  Referenced from: .../bin/nginx
  Expected in: flat namespace
```

**信号**：master 进程活着、日志打了 "using the kqueue event method"，
但 worker **立刻消失**、端口无监听、`nginx` 看起来 exit 0。
**修法**：`unset_macro NGX_HAVE_SETPROCTITLE`（走 nginx 自带的 env 方案）。

### 9.2 pkg-config 静默回退宿主库

`PKG_CHECK_MODULES([OpenSSL],[openssl])` 在 `PKG_CONFIG_PATH` 未设时会拿到
**宿主的 OpenSSL 3.5.5**，而不是交叉编译的 4.0.3。宿主库自然没有 armv7
目标，后续 `AC_CHECK_LIB` 必失败，报的却是：
`configure: error: found OpenSSL without AES support`。
**判据**：`pkg-config --modversion openssl` 在设/不设 PATH 时给出不同版本。
**修法**：设 `PKG_CONFIG_LIBDIR`（**不只是 PATH**——LIBDIR 是替换内置搜索
路径，PATH 只是追加），且**把每个交叉依赖都列进去**（只列 openssl 时下一
步就死在 `Package 'protobuf' not found`）。

### 9.3 AC_CHECK_LIB 的裸 -lxxx 在交叉链接下必失败

`AC_CHECK_LIB([crypto],[AES_encrypt])` 发的是裸 `-lcrypto`，交叉 ld64 的
搜索路径里没有它 → 报 no。但符号**确实存在**于我们的静态归档：
`llvm-nm-21 --defined-only .../libcrypto.a | grep _AES_encrypt` 有输出，
且手工 `cc-wrapper.sh t.c $OSSL/libcrypto.a -lz` 链接干净。
**修法**：预置 autoconf 缓存变量（`export ac_cv_lib_crypto_AES_encrypt=yes`），
这是 autoconf 官方认可的"陈述探针无法确定的事实"的手段；mosh 随后经
`CRYPTO_LIBS` 链真实归档。

### 9.4 相关：AC_PATH_PROG 只认 $PATH

`mosh/configure` 用 `AC_PATH_PROG([PROTOC],[protoc])` 找 protoc，**没有**
`--with-protoc` 选项。我们的 protoc 在 protobuf-host 前缀里、不在 PATH，
于是 `configure: error: cannot find protoc`。AC_PATH_PROG 尊重**同名环境
变量**，故 `export PROTOC=/path/to/protoc` 即可。

### 9.5 feature macro 要成组给

`wchar.h` 把 `wcwidth()` 守卫在
`#if defined(_XOPEN_SOURCE) || defined(_GNU_SOURCE) || defined(_BSD_SOURCE)`
之下（wcwidth 是 XSI 扩展，不是 POSIX）。只给 `_POSIX_C_SOURCE=200809L`
时声明消失，mosh 编译死在 `terminal.cc: use of undeclared identifier
'wcwidth'`。**修法**：`-D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700`
（700 = POSIX.1-2008 + XSI，与 200809L 同级），两者都要在 **configure 命令
行**上（automake 把 CPPFLAGS 烘焙进 src/Makefile，`make CPPFLAGS=` 无效）。

## 10. config.h 重生成陷阱：修正必须做在模板（2026-11-13）

**信号**：反复 sed 修好的 `#define HAVE_PLEDGE 1`，在 `make` 之后**又变回 1**，
无论改多少次。加打印可见 `pre-make PLEDGE=0` 而编译**仍**报
`use of undeclared identifier 'pledge'`。

**根因**：`src/include/Makefile`（automake 生成）带 autoconf 的 header 规则：

```make
config.h: stamp-h1
	@test -f $@ || rm -f stamp-h1
	@test -f $@ || $(MAKE) $(AM_MAKEFLAGS) stamp-h1
stamp-h1: $(srcdir)/config.h.in $(top_builddir)/config.status
	@rm -f stamp-h1
	cd $(top_builddir) && $(SHELL) ./config.status src/include/config.h
```

configure 刚跑完时 **config.status 比 stamp-h1 新**，于是第一次 make 重跑
`config.status`，**整体重写 config.h**，把事后 sed 全部推翻。

**修法**：改**模板** `config.h.in`——config.status 只把 `#undef NAME` 替换
成烘焙值，**其他内容原样拷贝**。所以：

- `#undef HAVE_PLEDGE` → 改成注释（不匹配替换模式，永久保持未定义）
- `HAVE_PTHREAD`（模板里**没有** `#undef` 行）→ 追加 `#define HAVE_PTHREAD 1`
- `touch config.h.in` 使其比 configure.ac/aclocal.m4 新，避免 autoheader 重生成

**配套铁律**：`#ifdef` 判断的宏**必须"未定义"，不能是 0**。
`#define HAVE_PLEDGE 0` 仍让 `#ifdef HAVE_PLEDGE` 为真 → pledge() 照样编进去。
（PLEDGE 是 OpenBSD 专有；iOS 没有。）

## 11. iOS 10 缺失的常用工具（2026-11-13 实测）

设备是精简用户态，**下列命令全部不存在**：

| 命令 | 状态 | 替代 |
|---|---|---|
| `netstat` | ❌ 无 | `lsof -nP -iTCP -sTCP:LISTEN`（实测有效） |
| `ifconfig` | ❌ 无 | `ipconfig getifaddr en0` / 读 sysctl |
| `route` / `arp` / `sockstat` | ❌ 无 | 见「移植 netstat」待办 |

**存在的**：`lsof`、`nc`、`curl`、`plutil`、`launchctl`、`ldid`、`dpkg`。
排查端口占用时**不要用 netstat**（会得到空输出而被误判成"没监听"，本轮
就因此白绕了一圈）；用 lsof，并用**主机侧直连**（`bash -c 'cat < /dev/null
> /dev/tcp/<host>/<port>'`）做交叉确认。

## 12. iOS 10 launchd 不自动加载新 plist（2026-11-13）

把 plist 放进 `/Library/LaunchDaemons/` **不够**：实测安装后
`launchctl list | grep nginx` 为空，进程也不起；手工
`launchctl load -w <plist>` 后立刻出现并拉起服务。
**修法**：deb 的 postinst 里显式 `launchctl load -w`；prerm 里
`launchctl remove <label>`（否则 KeepAlive 会把正在卸载的进程反复拉起）。

守护 nginx 这类**会自我 daemonize** 的程序还需要一层 wrapper：用
`-g 'daemon off;'` 让 master 留在前台，launchd 才监督得到（同
`dropbear-daemon.sh` 用 `-F` 的理由）。

## 13. `-undefined dynamic_lookup` 的静默失败与三件防雷工具（2026-11-13）

链接器带着 `-undefined dynamic_lookup`：**链接期任何缺失都不报错**，
运行期 dyld 才引爆——一天内在设备上炸出四颗雷，全部链接通过：

| 符号 | 来源 | 设备症状 |
|---|---|---|
| `_setproctitle` | sysroot 声明 + 只编译探针 | worker 秒死（§9.1） |
| `InternalMetadataD1Ev` | protobuf 库带 NDEBUG、消费方没带 | fork 子进程首条消息销毁时死 |
| `_uncompress`/`_compress` | **wrapper 丢弃 `-lz`**（"all inside libSystem"假设错，zlib 不在 libSystem）+ `-L+-lz` 搜索链失效 | launch 即 SIGABRT |
| `_recvmmsg`/`_sendmmsg` | OpenSSL 4.x 静态 socket 助手；iOS 10.3.3 XNU 无此 syscall | 惰性绑定，踩到即死 |

### 三件防雷工具（本次固化，后续移植必须走）

1. **`tools/check-undefined.sh <binary>`** — 链接后审计门禁（已接入
   mosh/nginx 的 build.sh，失败即构建失败）：每个 undefined 符号必须
   满足其一——(a) 在 tbd 桩或 `tools/sysroot/device-exports/` 的
   设备实测清单里；(b) 是设备 libc++ 符号（St3__1/St 命名空间、
   cxxabiv RTTI、基础类型 typeinfo、operator new/delete、__cxa_）；
   (c) `dyld_stub_binder`。其余一律 FAIL。
2. **`tools/probe-symbols.sh`** — 设备实测白名单生成器：把候选符号
   （nm -u 输出）生成为 `__DATA` 段 `.long` 重定位探针（**非惰性**，
   dyld 启动必须全部绑定），三件套部署到设备跑；dyld 报缺谁就剔除谁，
   循环收敛，存活清单落盘 device-exports。**教训**：探针编译失败必须
   致命（曾因吞掉编译错误产生 217/217 全通过的假阳性）；探针自身的
   符号（`__probe_tab`）不得进候选（Apple ABI 多一层下划线，曾致死循环
   ——已加无进展护栏）。
3. **`sysroot-overlay/usr/lib/libios-compat.a`** — 优雅降级桩库
   （`tools/sysroot-overlay-compat/`，cc-wrapper 自动附加在链接行
   **最末**）：recvmmsg/sendmmsg → ENOSYS；setupterm/tigetflag/tigetnum/
   tigetstr → curses ERR。设备没有的东西，桩给一个**可处理的错误返回**，
   而不是让 dyld 杀进程。未引用的成员不会被拉入。

#### 3.1 桩清单（按加入原因分组）

| 桩 | 触发包 | 说明 |
|---|---|---|
| `recvmmsg` / `sendmmsg` | mosh、（ffmpeg/tor 的 libssl 亦拖出） | → `ENOSYS` |
| `setupterm` / `tigetflag` / `tigetnum` / `tigetstr` | curses 类 | → curses `ERR` |
| **`pledge`** + 其余 5 个 | **mosh** | OpenBSD 专有系统调用，优雅降级（连同 `recvmmsg` 等共 6 个） |
| **`_pow10`** | **jq** | **忠实仿真**（`pow(10, x)`），不是空桩——见 `docs/jq.md` §3.4 |
| **`fflush_unlocked` / `fputs_unlocked` / `fread_unlocked` / `__fsetlocking`** | **wget** | glibc 的 `_unlocked` 变体；补后 wget **261/261 审计全绿**，见 `docs/wget.md` §5 |
| **terminfo 全家**（tmux/vim 路径） | tmux / vim | 冷路径，lazy 绑定 + 桩双保险 |
| **utmp 三件套** | — | 设备无 utmp；冷路径 |
| **BLAS：`daxpy_` / `ddot_` / `dnrm2_` / `dscal_`** | **node**（nmap 也触发过） | 冷路径 BLAS 符号 |
| **`_NSGetExecutablePath`** | node 等 | 存根**返回 `-1` 且 `buflen=0`**。曾因"设备应该有"而被探针**误拒**，实为需要显式存根（2026-11-14 审计后补） |

> **原则**：**冷路径符号进桩，热路径符号必须真解析**。
> 判据 = `check-undefined.sh` 门禁（`docs/toolchain.md` §13 第 1 件工具）。

### 排障时踩过的坑（本节配套）

- 设备 `/usr/lib/libSystem.B.dylib`、`libSystem.dylib` **打不开**——
  iOS 9+ 系统 dylib 都在 dyld 共享缓存里，独立文件是空壳。`nm -g` 一次
  空输出**不构成"未导出"的证据**（setproctitle 结论碰巧被 dyld 崩溃
  报告独立证实）。设备符号是否存在，以 `probe-symbols.sh` 实测为准。
- mosh 的 protobuf 头按 NDEBUG 二选一（§10 同源）：库带 NDEBUG 时，
  消费方也必须 `-DNDEBUG`，否则析构走外联分支引用不存在的符号。
- nginx 的 zlib 正常是因为它用**显式 .a 路径**（wall #4）；`-L+-lz`
  在 wrapper 链路下不工作（wrapper 丢 `-lz`，探针实测对照确认）。
- automake 的 `Makefile: config.status` 规则会在首次 make 时重新生成
  Makefile——**对 Makefile 的 sed 修正必须紧跟 touch**（同 §10
  config.h 的教训）。

## 14. netstat 移植：自备 ABI + 设备实测闭环（2026-11-13）

### 14.1 为什么不移植公开 netstat（Apple/FreeBSD）
Apple network_cmds（network_cmds-481.20.1）和 FreeBSD netstat 都 include
`sys/socketvar.h` / `netinet/tcp_var.h` 等内核私有头，这些头在 iOS 10.3.3
sysroot 里**不存在**。移植它们的第一件事就是补全这些头，工作量等同于自备 ABI。
我们的选择：直接抄内核导出结构（`xinpgen`/`xinpcb`/`xtcpcb`/`xsocket`/`otcpcb`），
用探针在设备上实测锚定每个字段偏移，**静态断言钉死尺寸**，编译期即失败不产出垃圾。

### 14.2 四轮探针链（每轮落盘、与 lsof 交叉验证）
| 探针 | 目的 | 关键发现 |
|---|---|---|
| `probe1` | MIB 可见性、链步长、首尾 xinpgen | TCP 524B、UDP/raw 320B、xinpgen 24B 算术闭合 |
| `probe2` | 字段偏移（端口、地址、状态、proto/family、rcv/snd） | 端口/状态/协议全对，地址存 v4-compat 形式（::a.b.c.d）非 ::ffff |
| `probe3` | v4-compat 地址修正（前 12 字节为零即视为 v4） | 地址修正后与 lsof 完美对齐 |
| `probe4` | IFLIST2 消息链结构（RTM_IFINFO2 + RTM_NEWADDR） | IFP sockaddr_dl 在 IFINFO2 里带名字+MAC，NEWADDR 仅带 IFA/NETMASK |

### 14.3 关键 ABI 静态断言（netstat.c 编译期钉死）
```c
typedef char _assert_xig[(sizeof(struct xig) == 24) - 1];
typedef char _assert_xso[(sizeof(struct xso) == 100) - 1];
typedef char _assert_inpcb[(sizeof(struct inpcb_compat) == 208) - 1];
typedef char _assert_otcpcb[(sizeof(struct otcpcb) == 204) - 1];
typedef char _assert_xinpcb[(sizeof(struct xinpcb_e) == 320) - 1];
typedef char _assert_xtcpcb[(sizeof(struct xtcpcb_e) == 524) - 1];
typedef char _assert_tstate[(offsetof(struct xtcpcb_e, tp.t_state) == 244) - 1];
```
内核若升级导致结构变化，**编译直接报错**，不会产出错误输出。

### 14.4 输出格式（按 BSD/Darwin 习惯）
- `-t`：仅活跃 TCP，带 `(state)` 列
- `-a`：含 LISTEN + UDP/raw，`*.port` 通配、`tcp4/tcp6` 双栈标注
- `-r`：`default` 标注、Netif 由 IFP sockaddr_dl 解出、`Expire`=剩余秒
- `-i`：13 个接口全显示（名字、MTU、MAC、统计、IPv4/6 地址）

### 14.5 审计门禁
`tools/check-undefined.sh`：**23/23 undefined 符号全解自 device libSystem**（纯 tbd 桩）。
无 libios-compat.a 依赖、无平台框架、无私钥路径。

### 14.6 sysroot 补全
仅 `sysroot-overlay/usr/include/net/if.h` 补 `struct ifa_msghdr`（7 字段，xnu-3789.70.16 逐字复制，
`[device-verified 2026-11-13]` 注记）。无需 `in_pcb.h`/`tcp_var.h`/`socketvar.h` 等私有头。

### 14.7 打包：deb 成员必须 gzip（2026-11-14 设备实测）
首版 deb 被宿主机新版 dpkg-deb 默认压成 `control.tar.zst`/`data.tar.zst`，
设备 dpkg 1.18.10 报 `unknown compression for member 'control.tar.zst'` 拒装
（二进制本身和签名都没问题，纯粹是容器压缩格式）。`netstat/make-deb.sh`
已钉 `dpkg-deb --root-owner-group -Zgzip --build`（与 lsof/make-deb.sh 同款）。
信号 → 动作：设备 `dpkg -i` 报 unknown compression → `ar t 包.deb` 看成员
后缀，非 .gz 即在 make-deb.sh 钉 `-Zgzip` 重建。另：GitHub Release
`apps-20261113` 里的 netstat4 是 zst 版装不上，需换传 gz 版。

## 15. configure 交叉移植四板斧（2026-11-14，rsync/less 沉淀）

1. **`ac_cv_func_*` 恒真陷阱**：cc-wrapper 链接带 `-undefined dynamic_lookup`，
   autoconf 的"自己声明 `char fn()` 再链接"存在性探针**永远成功**——设备
   根本没有的 glibc-ism（mallinfo2）也会被判 yes，然后死于编译期
   incomplete type 或运行期 dyld 缺符号。对策：显式压掉已知 glibc-ism
   （rsync 压了 mallinfo/mallinfo2/setattrlist/getattrlist/attropen/
   chflags/lchmod/mknod/linkat/acl_get_file/lseek64/open64），然后
   **`tools/check-undefined.sh` 门禁兜底**（它就是为这坑生的）；真有但
   tbd 白名单没收的符号走 `tools/probe-symbols.sh` 设备实测 →
   追加 `tools/sysroot/device-exports/`。
2. **注释禁入续行链**：`VAR=x \` 下一行以 `#` 开头 = `#` 连同行尾反斜杠
   一起进注释，续行断裂，**整串 env 覆盖静默失联**（rsync 一天栽两次）。
   规则：注释全部放赋值块上方；configure 之后**断言覆盖已生效**
   （grep config.h 里关键 define 的存在/不存在，不符即 FATAL）。
3. **手写 sysroot 的头是精简版，探针假阴性要手动复现**：sys/time.h 只有
   11 行、不提供 NULL → gettimeofday(&tv,NULL) 探针（只 include
   sys/time.h）假阴性；sys/xattr.h 是 Linux 4 参签名（macOS 6 参代码
   编不过）；无 sys/attr.h（lsof 早就绕过）。信号：探针结论与平台常识
   矛盾 → 手动复现探针看真实报错，别信结论；能喂缓存变量的喂真相，
   系统性缺口记 backlog（sys/attr.h、xattr.h 达尔文化）。
4. **git 树 ≠ 完整构建源**：rsync/less 的 git 树都缺生成物（rsync 的
   configure 探针在 configure.sh；less 的 funcs.h/help.c/less.hlp 只在
   release tarball 里）。信号：`No rule to make target` / 缺 .c →
   换官方 release tarball 当构建源（less-668.tar.gz 一把全齐）。
   tarball 下载后先 `tar -t` 验真（sourceforge/Debian 直链给过 HTML 壳）。

## 16. SDK sysroot 模式（2026-11-15 共存验证通过；同日拍板：新移植默认走此模式）

真 Apple SDK 已落位：`~/ios-tool/iPhoneOS10.3.sdk`（xybp888/iOS-SDKs 的
iOS-SDKs release zip，与设备 iOS 10.3.3 精确同版本；157 头条目、178 个
usr/lib 官方 tbd、91 框架）。

**用法**（与 musl sysroot 共存，不切换默认）：

```sh
export IOS_SYSROOT=$HOME/ios-tool/iPhoneOS10.3.sdk
export IOS_STUBDIR=$HOME/ios-tool        # 注意：仍是手写 stub 目录！
```

- **头**：SDK 的 usr/include 全量 Apple 头（NULL/getopt/net 系缺口一次性
  消失；libc 头即设备真身）。
- **`-lSystem` 锚点仍用手写 libSystem.tbd**：SDK 的 libSystem.tbd 是
  re-export 壳，re-export 指向设备绝对路径 /usr/lib/system/*.dylib——
  cctools ld64 会去宿主机追这些路径然后 `file not found` 退出
  （连 `cc-wrapper --version` 探针都炸，configure 直接"cannot create
  executables"）。手写 tbd 无 re-exports，`-lSystem` 锚定后其余符号走
  dynamic_lookup 由设备绑定，审计白名单（sdk-*.tbd 已入
  `~/ios-tool/`）确认设备真实性。
- **ac_cv 压制清单仍需要**：dynamic_lookup 恒真探针是编译器侧行为，
  换头不解决；且 SDK 头世界有新差异（utimensat 在 iOS 10 不存在）。
- **override 一律用独立 export 行**：注释吞续行反斜杠事故四个文件里
  发生过五次（make×2、tor×1、rsync×2）——export 行自包含无链，注释
  随便插；configure 后断言兜底。
- **金丝雀已过**：whois（Makefile 型，实弹查询）✓；rsync（configure+gnulib
  型，增量同步 245B/1618×）✓。两类型代表都干净，SDK 模式可用于新移植。
- **默认已拍板**（2026-11-15）：新移植一律 SDK 模式（AGENTS.md 工作规则
  5）；已上线 24 包是 musl sysroot 产物，不重编，可复现性保留在 git。

## 17. 设备 UUID 复测：SDK 头 availability ≠ 设备现实（2026-11-15）

三路实测（探针源码 `~/scratch/uuid-probe/`，二进制部署三件套签名）：

- **libSystem `uuid_*` API 全正常**：uuid_generate（连续 3 次互异 v4）、
  generate_random、parse/unparse 往返 rc=0，root/mobile 双身份各过。
- **内核 `gethostuuid()` 头标 `__IPHONE_NA`，设备符号却存在且可用**：
  dlsym(RTLD_DEFAULT) 拿到、调用成功，返回稳定主机 UUID（两次一致）。
  **结论：SDK 头的 availability 标注不是设备事实。** 以后遇到"头说
  iOS 没有"的函数（`__IPHONE_NA` / `__OSX_AVAILABLE` 系），先 dlsym
  复核符号在不在，再决定 shim/放弃，不要按头文件宣判。
- **BigBoss `uuid` 1.6.0-2p 的 `/usr/bin/uuid` CLI 是死的**：dyld 解析
  `libgcc_s.1.dylib` 经 libSystem.B 的 re-export 失败，Abort trap 6
  （三次复现）。2008 年老包兼容性烂，与设备 UUID 体系无关。
- **填补**：仓库第 25 包 `uuidgen`（e2fsprogs 1.47.2 misc/uuidgen.c，
  SDK 模式首移植，`uuid/build.sh`）。默认/-r v4、-t v1 实弹验证通过；
  `uuid_unparse` 大写输出是 e2fsprogs 上游行为。安装后注意：设备
  登录 shell PATH 只有 `/usr/bin:/bin`，`/var/mobile/tools/bin` 下的
  工具（含 uuidgen/node）日常要走绝对路径或自行 alias——既有环境
  现状，非本包问题。

## 18. FFmpeg 9.0.2 移植（2026-11-15，26 号包，SDK 模式最大工程）

全编解码器静态 CLI（ffmpeg+ffprobe 各 ~23MB，deb 19MB gzip）。
configure 阶段即暴露一批工具链通用雷，全部修复并回写 cc-wrapper：

- **`-Wl,a,b` 逗号语义**：GNU 链接器的 `-Wl,` 逗号串要拆成独立参数
  （`-Wl,-dynamic,-search_paths_first` 整串直喂 ld64 = unknown option）。
  wrapper 已改：逐逗号拆分转发。
- **`-isysroot <path>` 分立形式**：flag 与路径是两个参数，路径不能漏进
  CFLAGS（"linker input unused" 警告源头）。wrapper 已改。
- **SYSTEM_FUNCS 恒真探针窝**：ffmpeg 探测几十个系统函数
  （`check_func`），dynamic_lookup 下全部恒真——Windows/BSD/Linux
  专属函数（closesocket/gethrtime/pthread_setaffinity_np/sched_getaffinity
  等 20 项）误进 config.h，`closesocket` 宏失效直接编译报错。
  `--disable-XXX` 不达 SYSTEM_FUNCS（只在 CONFIG/HAVE_LIST 作用域），
  修法 = configure 后、make 前 sed config.h 压制 + grep 断言。
  ffmpeg 的 config.h 仅 configure 时生成、make 不重写，修正不丢。
- **darwin 分支无条件挂四框架**：CoreFoundation/CoreMedia/CoreVideo/
  CoreAudio 的 `check_apple_framework`（configure 7119-7122）不看
  videotoolbox 开关，探测过了就把 `-framework` 写进 EXTRALIBS——
  必须给 ld64 框架搜索路径：`--extra-ldflags` 加
  `-F$SDK/System/Library/Frameworks`（wrapper 的 -F 双投递）。
- **gas-preprocessor.pl**：arm/aarch64 汇编通道是 configure 自动探测
  （PATH 里有就采用）；本工程 NEON/VFP 汇编实编通过，未用
  --disable-asm（降 arch=c、DSP SIMD 全灭，A6X 性能崩）。
- **lavfi 缺失**：`-f lavfi` 输入属 libavdevice（本包 --disable-avdevice），
  验收素材从宿主造（testsrc2 mp4 / sine wav）scp 上去。
- **验收**（mobile 身份）：-version ✓；h264 解码→mpeg4 编码 ✓；
  wav→aac 编码 ✓；aac 解码回路 ✓（字节数合理）；ffprobe 双产物
  元数据全对 ✓；链接审计 ffmpeg 288/288、ffprobe 283/283 符号
  全部 tbd 可解析 ✓。

## 19. Apple armv7 的 8 字节原子是**对齐陷阱** → SIGBUS（2026-11-16 定论）

> **结论曾于 2026-11-16 晚修正**：早期记为"静默失败（写不进、不崩溃）"，
> 实测**是 SIGBUS 硬崩**。死锁与崩溃是同一约束的两种症状，见下。

**症状**（两种，取决于 8 字节对象碰巧落在什么地址上）：
- **非对齐** → `Bus error: 10`，进程当场死，**且不产生崩溃报告**
- **恰好 8 对齐** → 能跑，但值不对 / 单线程自己等自己（死锁）

**根因**：Apple 32 位 ARM ABI 给 `int64_t` / `unsigned long long` / `double`
的**自然对齐是 4 字节**（Linux armv7 是 8）。但 ARM 的 `ldrexd`/`strexd`
（8 字节原子的独占访问实现）**要求 8 字节对齐**。clang 按 ABI 排布对象后
生成非对齐的 `ldrexd` → **CPU 抛对齐异常 → SIGBUS**。

设备探针（`scratch-probe/atomic8.c`）：

```
sizeof(int64_t)=8   _Alignof(int64_t)=4
&g_val = 0x72024    (mod 8 = 4)
__atomic_load_n(&g_val, __ATOMIC_RELAXED)  ->  Bus error: 10
```

| 场景 | 结果 |
|---|---|
| 4 字节对齐 + 8 字节原子 | ❌ **SIGBUS** |
| 拆成两个 32 位原子 | ✅ 正确 |
| 8 字节对齐 + 8 字节原子 | ✅ 正确 |

**关键陷阱**：`__attribute__((aligned(8)))` 加在**字段**上无效——编译器
按**类型**的自然对齐判定，不看字段声明对齐。

**判别方法**（三步定位）：
1. 编译期看警告：`-Watomic-alignment`（"expected alignment (8 bytes)
   exceeds the actual alignment (4 bytes)"）——**这警告必需当错误看待**
2. 运行期：8 字节原子 store/load 一个 4 对齐对象，崩就是它
3. 隔离探针：4 字节 vs 8 字节原子各自对比（见上表）

**修法**：把 8 字节原子拆成两个 4 字节原子 + 两半之间加屏障。
- **不要只修撞到的那一个函数**——python3 首次移植只改了
  `_Py_atomic_load_ullong_relaxed`，留下 18 个 int64/uint64 入口，
  后来 `socket.socket()` 100% SIGBUS（崩在 `_Py_atomic_load_int64_relaxed`）。
- 系统化脚本：`python3/patches/patch-atomic-armv7-align.py`（幂等，
  3.13/3.14 通用，覆盖 5 load + 5 store）。
- **读-改-写类**（add / exchange / CAS / and / or）拆半会破坏原子性，
  需锁或重试循环，该脚本**未覆盖**——将来新崩溃优先查这几个。

**历史呼应**：node 移植墙 #11（`___atomic_load_8` 被当成 no-op，用
`c8fixed.o` 强制 `is_lock_free` 只认 ≤4 字节）——**同一根因的第一次现身**。
**凡在 armv7 Apple 上移植带锁/原子计数的软件，先检查这一条。**

## 20. O_NONBLOCK:把所有问题都藏起来的那个 bug（README 迁入 2026-11-19）


Worth reading even if you never build for iOS, because it produced weeks of
blaming the wrong layer.

The sysroot started from musl, whose `fcntl.h` is Linux's:

```
musl/Linux:  O_NONBLOCK = 0x800     (and O_CLOEXEC = 0x80000)
Darwin:      O_NONBLOCK = 0x4       (and O_CLOEXEC = 0x1000000)
```

`fcntl(fd, F_SETFL, 0x800)` on Darwin sets an unrelated bit and *does not set
non-blocking mode* — and fcntl never fails on an unknown flag, so every
"make this socket non-blocking" in the entire program was a **silent no-op**.
Every socket stayed blocking.

Symptoms this one constant produced:

* the client hung forever inside libevent's signal-pipe drain loop
  (`evsig_cb` reads until EAGAIN; on a blocking fd with no data left it simply
  blocks, and the client never called `poll()` again — proven with a watchdog
  and a debug `poll()` wrapper);
* a peer's data sat unread while both processes were alive and sleeping;
* `MSG_EXIT` was queued but the peer never saw it;
* behaviour changed randomly between runs and between the select/kqueue/poll
  backends, because blocking fds make every event-loop race resolve
  differently.

`F_GETFL`/`F_SETFL` (3/4) match Darwin by pure luck, which is why fcntl calls
never failed loudly. `O_CLOEXEC` being wrong also leaked fds into pane
children.


## 21. Darwin ABI 陷阱总表（README 迁入 2026-11-19；与 §8 互为索引）


Each of these produced its own bug before being fixed; the fixes live in
`sysroot-overlay/usr/include/`:

| header | trap |
|---|---|
| `bits/errno.h` | `EAGAIN` 11 (Linux) vs 35 (Darwin): every `errno != EAGAIN` treats "try again" as fatal |
| `sys/socket.h` | `SOL_SOCKET` 1 vs `0xffff`: `sendmsg`+`SCM_RIGHTS` fails with `EINVAL`, so a client cannot hand its tty to a server |
| `fcntl.h` | `O_NONBLOCK`/`O_CLOEXEC` as above |
| `pwd.h` | Darwin inserts `pw_change`/`pw_class`: musl's layout made `pw_shell` read `pw_gecos` — tmux tried to exec a shell named "Mobile User" |
| `termios.h` | musl adds `c_line`; every offset after it differs |
| `sys/utsname.h` | Darwin `char[256]x5` vs musl `char[65]x6`: `uname()` overflows the caller's stack by ~890 bytes and corrupts adjacent buffers (tmux parsed `list-windows` as `liPad3,4`) |
| `bits/signal.h` | signal numbers, `SA_*`, `sigset_t` |
| `sys/ioctl.h` | `TIOCGWINSZ` and friends are completely different ioctls |
| `unistd.h` | `closefrom` does not exist on iOS 10; autoconf probes always succeed because the linker tolerates undefined symbols, so it must be disabled by hand and replaced by the project's bundled copy — it aborts in the forked child of every new pane, visible only in `/var/mobile/Library/Logs/CrashReporter/*.ips` |

Later additions, found while porting OpenSSL 4 and curl 8:

| header | trap |
|---|---|
| `pthread.h` | musl's `pthread_once_t` is a 4-byte `int`; Darwin's is a 12-byte `{long __sig; char __opaque[8]}` with `_PTHREAD_ONCE_SIG_init = 0x71B7236C`. Every `CRYPTO_ONCE`/`pthread_once` therefore corrupts memory and aborts inside `os_once` with `BUG IN CLIENT OF LIBPLATFORM: Unlock of an os_once_t not owned by current thread`. Also carries the 32-bit `pthread_mutex_t` (44), `cond` (28), `rwlock` (128) and `attr` (40) layouts, and Darwin's `PTHREAD_CREATE_DETACHED = 2` (Linux says 1). `bits/alltypes.h` must surrender its 14 `__NEED_pthread_*` typedef blocks, and `sys/types.h`/`signal.h`/`mqueue.h` their `__NEED_pthread_*` defines, or the two definitions collide |
| `netinet/in.h`, `sys/socket.h` | **No `sa_len`/`sin_len`.** Darwin's `struct sockaddr` is `{u_char sa_len; sa_family_t sa_family; ...}` with the length first; musl omits it and its `sa_family_t` is 16-bit. Without the leading byte, `inet_ntop()` reads a 16-bit family from offset 0, gets `0x0210`, and fails with `EAFNOSUPPORT` — curl reports `connect to port 0 failed: Address family not supported by protocol family`. Sizes that must come out right: `sockaddr` 16, `sockaddr_in` 16, `sockaddr_in6` 28, `sockaddr_storage` 128 |
| `sys/socket.h` | `SOCK_NONBLOCK`/`SOCK_CLOEXEC` **do not exist on iOS 10.** musl hands out `0x80000`; curling ORs `SOCK_NONBLOCK` into the socket type, the kernel answers `EINVAL`, and every connection dies in ~1 ms with "Failed initialization". Probing every candidate bit showed only the low two bits are even meaningful (`0x2`/`0x4` are `SOCK_DGRAM`/`SOCK_RAW`; `0x8`…`0x40` are rejected). The overlay `#undef`s both so callers fall back to `fcntl(F_SETFL, O_NONBLOCK)`, which works because `O_NONBLOCK` is already corrected |
| `netdb.h` | `h_errno` is a Darwin global that musl does not declare |
| `netinet/in6.h` | `struct in6_pktinfo` plus Darwin's option values: `IPV6_PKTINFO` 46 and `IPV6_RECVPKTINFO` 61, **not** the Linux 50/49. `netinet/in.h` must not also define the Linux `IPV6_*` block, or those values win by being included second |
| `TargetConditionals.h`, `libkern/OSByteOrder.h` | Apple-only headers OpenSSL includes unconditionally; clean-room stubs |

A third round, found while porting GNU wget 1.25.0.  One entry is not a new
trap but a correction to the row above, and it is the most instructive of the
lot:

**The `sa_len` fix in the `sys/socket.h` row above was never actually made.**
`netinet/in.h` got `sin_len`, but `sys/socket.h`'s `struct sockaddr` still
starts at `sa_family`, so the README described a fix the tree did not contain
(`git log -S'sa_len'` shows the symbol was never committed there until it was
added for wget).  Nothing noticed because curl passes the `sockaddr` that
`getaddrinfo()` returns straight back to `connect()` — the *system* fills the
memory in, so a wrong header still byte-counts 16 and works.  wget's own
socket layer inspects the struct, so it fails at once: `getaddrinfo()`
resolves correctly and then every address fails `connect()` with
`EAFNOSUPPORT`.  The lesson generalises: a header that is wrong in a way that
only matters to code that *touches* the field will pass every test you already
have, and the size is not a safety net because musl's and Darwin's
`sockaddr` are both 16 bytes with different layouts.

| header | trap |
|---|---|
| `sys/socket.h` | `sa_len` missing from `sockaddr`, and `ss_len` from `sockaddr_storage` (which also used musl's padding and came out 136 bytes instead of 128) — see the paragraph above |
| `stdlib.h` | `MB_CUR_MAX` was `__ctype_get_mb_cur_max()`, a **glibc** internal.  Darwin exports a plain `int` variable, `__mb_cur_max`.  Measured on the device: the function form aborts with `dyld: lazy symbol binding failed: Symbol not found: ___ctype_get_mb_cur_max`; the data form returns 1 and survives `setlocale()`.  Calling the data symbol *as a function* bus-errors, which is how the two were told apart.  Any program using `MB_CUR_MAX` died at first use, not at link time |
| `unistd.h` | six declared-but-absent functions are declared here after being confirmed on the device one at a time: `getpgrp`, `setpgrp`, `fdatasync`, `sbrk`, `ualarm`, `fpathconf` and `issetugid` (wget 1.25 needs `getpgrp`, gnulib needs `issetugid`) |
| `sys/stat.h` | no `st_birthtim` alias for `st_birthtimespec`, so gnulib's `stat-time.h` fails with `no member named 'st_birthtim' in 'struct stat'` |
| `netinet/in6.h` | musl omits `IN6_ARE_ADDR_EQUAL` outright.  Also fixed a typo in `IN6_IS_ADDR_LOOPBACK`: a stray second dereference meant the second word was never compared, so the macro accepted **every** IPv6 address as a loopback |
| `unistd.h` (again) | Darwin's `pathconf` selectors are not Linux's — `_PC_NAME_MAX` is **4**, not 3.  Established by binary-search over `open()`: the filesystem rejects a 256-character path component with `ENAMETOOLONG`, and selector 4 is the one that returns 255.  A jailbroken device has no `/usr/include`, so this constant has to be measured, not copied from a header you do not have |
| `xlocale.h` | Apple deleted it years ago (its contents moved into `<locale.h>`); gnulib's `localcharset.c` still includes it for `MB_CUR_MAX_L` whenever it defines `DARWIN7` |
| `spawn.h` | Darwin represents `posix_spawnattr_t` and `posix_spawn_file_actions_t` as **4-byte opaque pointers**, not musl's 80- and 72-byte by-value structs.  Measured on the device: `posix_spawnattr_init()` writes 4 bytes into an `0xAA`-filled buffer and leaves the rest untouched |

**`libSystem` is missing compiler-rt's generic atomics.** clang lowers OpenSSL's
`CRYPTO_atomic_*` on armv7 to `__atomic_load`, `__atomic_store`,
`__atomic_compare_exchange` and `__atomic_is_lock_free`, none of which iOS 10
exports. clang also refuses to let C code define them (`cannot redeclare builtin
function`, even with `-fno-builtin-<name>`), so `openssl/atomic_compat.c`
implements them under internal names with a libgcc-style lock table and
`openssl/atomic_alias.s` provides the public symbols as Mach-O long-branch
stubs (`ldr pc, [pc, #-4]`).

**Autoconf link tests always succeed here.** Because the kit links with
`-undefined dynamic_lookup`, a `checking for eventfd... yes` is worthless: the
symbol is simply left undefined and dyld aborts at first use
(`dyld: lazy symbol binding failed: Symbol not found: _eventfd`). Every Linux-only
function a project probes for — `eventfd`, `pipe2`, `accept4`, `recvmmsg`,
`sendmmsg`, `getpass_r`, `gsasl_init` — has to be switched off by hand after
`configure` runs.

Debugging tips that actually worked, in order of usefulness:

1. **Read the crash reports first.** A dyld abort produces no other output;
   `Termination Description: DYLD, Symbol not found: _closefrom` ended days of
   guessing.
2. **Compare the failing program with a minimal one on the device.** A 60-line
   program that performs the same registration pattern either reproduces the
   fault (libevent/platform bug) or passes (program logic bug).
3. **Instrument the platform libraries.** A debug `fprintf` around `poll()`
   showing the fds, requested events and returned `revents` settles arguments
   about "lost wakeups" immediately.
4. **Bisect with a throwaway program against the same headers.** When curl
   failed to connect in 1 ms but `ssh` from the same device worked, a 30-line
   `socket()`/`connect()` program passed and a `getaddrinfo()` one passed too —
   which proved the kernel and resolver were fine and pushed the search into
   curl's own socket setup. Probe the *candidate constant* directly: looping
   `socket(AF_INET, SOCK_STREAM | bit, 0)` over single bits found that iOS 10
   accepts none of them.


## 22. Darwin 头获取流程：fetch-darwin-header.sh（README 迁入 2026-11-19）


`tools/fetch-darwin-header.sh` exists because the loop

> find the header -> take the definition from upstream -> prove it on the device

was repeated by hand about twenty times across the ports (tmux, curl, lsof,
dropbear, openssh, node), and because **every mistake in that loop was a
confidently-written wrong value**, not a syntax error.

```sh
./tools/fetch-darwin-header.sh sys/filio.h          # print source + provenance
./tools/fetch-darwin-header.sh sys/event.h --install  # stamp + sync into overlay
./tools/fetch-darwin-header.sh mach/boolean.h --probe # also emit a device probe
```

What it does:

1. **Resolves the header from an authoritative source**, in order: the local
   xnu sparse clone (tag `xnu-3789.70.16`), the Libc clone, cctools' `foreign/`
   headers, the libdispatch clone, then GitHub over HTTP for anything else.
   It prints where it got the text so the provenance ends up in the file.
2. **Installs with a provenance comment** into `sysroot-overlay/usr/include/`
   and syncs to `tmp/sysroot` with an `rsync --include='*.h'` filter. It will
   not overwrite an existing, differing header without `--force` — the overlay
   is a working tree every build depends on.
3. **Checks** the result before it can break a build: include-guard pairing,
   `extern "C"` presence, and a "Darwin does not have this at all" list
   (`SIGPWR`, `SIGSTKFLT`, `SIGPOLL`, `sendmmsg`/`recvmmsg`, ...). A failed
   check exits non-zero.
4. **Writes a probe skeleton** with `--probe` that carries the exact compile /
   sign / scp / run sequence for the device, and the rules learned the hard
   way.

The third step of the loop — proving the value on the device — is the only one
that cannot be automated, and the probe skeleton leaves the asserts to you.
Nothing in this port is believed until the device says so:

| Symbol | Value | How it was settled |
|---|---|---|
| `F_GETPATH` | 50 | swept fcntl numbers 45..55, found the one returning a path |
| `MCAST_JOIN_GROUP` | 80 | xnu (`bsd/netinet/in.h`) — Linux is 42 |
| `MAP_MEM_NAMED_CREATE` | `0x20000` | cctools `foreign/mach/memory_object_types.h` |
| `malloc_zone_t` `size` | offset 16 | found by calling `zone->size(zone, p)` |
| `IP_TTL` | 4 | xnu — Linux is 2 |
| `SIGPWR` / `SIGSTKFLT` | *absent* | device signal dump showed the collisions they'd cause |


## 23. SDK 头是"公开裁剪版":内核私有段要用 xnu 完整头 + `-DPRIVATE`(2026-11-20,ifconfig 移植确立)

iOS SDK(`~/ios-tool/iPhoneOS10.3.sdk`)的内核系头(`net/if.h`、
`sys/sockio.h`、`net/if_var.h` 等)是 **PUBLIC cut**——xnu 同名头里所有
`#ifdef PRIVATE` 段被整体删除。Apple 自家工具(network_cmds 系 ifconfig/
route/arp)却构建在这些 PRIVATE 段上(`if_descreq`、`SIOCSIFDESC`、
`if_bandwidths`、`if_traffic_class`……)。撞墙形态全是
"incomplete type / undeclared identifier",且名字都能在 xnu 源里找到——
这就是"头被裁过"的签名。

**模式(端口自带 include/,不污染共享 overlay):**

```sh
# xnu-3789.70.16 = 设备内核精确版本;从本地 sparse clone 落头
git -C ~/scratch/sysctl-work/xnu cat-file -p xnu-3789.70.16:bsd/net/if.h
# build.sh:
"$CC" -O2 -Wall -DPRIVATE -I"$here/include" -o ...   # §1 环境变量整块带上
```

- include/ 只放 **SDK 真缺的**(fetch-darwin-header.sh 拉取、extern "C"
  门禁处理)+ **必须整头换用的 shadow**(net/if.h、net/if_var.h、
  sys/sockio.h),SDK 其余头原样生效。
- **shadow 陷阱**:`-I` 指向装满 xnu 头的大目录会遮住 SDK 同名头
  (overlay 的 `sys/param.h` 引 `endian.h` 直接雪崩)。include/ 必须
  最小化,这与 §22 的 overlay 用法(musl sysroot 时代)不同。
- `-DPRIVATE` 会打开所有 PRIVATE 段:注意 `uuid_t` 这类类型在内核世界
  来自 KERNEL 侧头,用户态要补 `sys/_types/_uuid_t.h`(SDK 自带)。
- `tmp/sysroot` 是 musl 时代的旧 sysroot(epoll.h/inotify.h 都在),
  §16 拍板后只服务存量 24 包,新移植禁止;它连 SDK 自带的
  `sys/queue.h` 都没有。
- kldload/modstat(sys/module.h、sys/linker.h)在 Apple 的 C 源里已
  包 `#ifndef __APPLE__`,零补丁。
- 权限裁决:ifconfig/route 装成 root:wheel 0755、**不 setuid**——
  接口 ioctl(SIOCAIFADDR)与 route add/delete 需 root;setuid 的话
  等于把 en0 down 的能力交给 mobile。只读状态(mobile)与写操作
  (root ssh)的边界在 docs/ifconfig.md §4 实测定界。

适用:network_cmds 家族后续移植(arp/ndp/ip6fw……)与任何引用内核
PRIVATE 段的工具。iproute2 本身无 Darwin 版(netlink 专属),BSD 侧
对应物就是 ifconfig + route + netstat。
