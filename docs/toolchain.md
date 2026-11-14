# 交叉编译工具链通用规则（iPad4 / armv7 / iOS 10.3.3）

> 适用范围：所有为这台设备交叉编译的软件（node、quickjs、dropbear、openssh、
> openssl、curl…）。软件专项细节见同目录各 md；本文只写**工具链层面可复用的规则**。
> 维护：大肥鱼。正本在本 git 仓库 `docs/`；`~/.dsh/AGENTS.md` 是它的符号链接入口。

## 1. 构建环境（每次都要 export）

```sh
export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot
export IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
```

- C 驱动：`~/ios-tmux-builder/tools/cc-wrapper.sh`
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
- 症状特征：插入成功、紧跟的查找失败；成功/失败集合随构建漂移（栈垃圾决定）。

## 5. 部署与验证

- 部署三件套（缺一 exec 即 SIGKILL）：`chmod 755 X && chown mobile:mobile X && ldid -S X`
- 排查 SIGKILL 第一步：设备上 `ldid -e X`——有输出=已签名；
  `_assert(signature != NULL)`=未签名。
- 就地覆盖已存在文件有 vnode 风险 → **部署成新文件名，再 `rm -f` 旧名 + `cp`**。
- 崩溃报告：`/var/mobile/Library/Logs/CrashReporter/*.ips`（SIGKILL 无报告；
  连续崩溃会被限流）。
- **.ips 符号化**：报告里 `0xADDR base + off` 的 base 是设备加载基址；
  主机地址 = `host_TEXT_vmaddr(0x4000) + (dev - base)`。必须用**同字节**
  的未 strip 孪生体（`llvm-nm -n` + 二分，或 llvm-symbolizer-21 --obj）；
  跨构建符号化漂移 KB 级，不可用。
- 探针模板（构建+部署+跑）：

```sh
export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
~/ios-tmux-builder/tools/cc-wrapper.sh -O1 -o /tmp/probe /tmp/probe.c [额外 .o/.a]
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
