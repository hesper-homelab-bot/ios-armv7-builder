# 交叉编译工具链通用规则（iPad4 / armv7 / iOS 10.3.3）

> 适用范围：所有为这台设备交叉编译的软件（node、quickjs、dropbear、openssh、
> openssl、curl…）。软件专项细节见同目录各 md；本文只写**工具链层面可复用的规则**。
> 维护：大肥鱼。正本在本 git 仓库 `docs/`；`~/.dsh/AGENTS.md` 是它的符号链接入口。
>
> **结构说明（2026-11-20 拆分，两轮）**：本文只保留**跨包通用**的工具链规则。
> ① musl 时代手搓 sysroot（2026-11-06~11-15，现 `tmp/sysroot`）的头改写史、
> 运行时 ABI 规则、O_NONBLOCK 案例与 Darwin ABI 陷阱总表 →
> **`docs/musl-sysroot.md`**；② 各移植软件的内部雷全录（autoconf 实录、
> config.h 陷阱、netstat 自备 ABI、UUID 死因、FFmpeg 构建雷）→
> **各自 `docs/<pkg>.md`**（§9/§10/§14/§15/§17/§18 留速查桩与指针）。
> SDK 模式自 2026-11-15 起为默认（§16，公开裁剪头问题见 §23；2026-11-20
> 修订：存量包新版本也走 SDK）。历史章节号保留不重排（外部文档引用
> §8/§13/§14/§22 等）。

## 1. 构建环境（每次都要 export）

```sh
# SDK sysroot 模式（2026-11-15 起新移植默认，§16/§23）：
export IOS_SYSROOT=$HOME/ios-tool/iPhoneOS10.3.sdk
export IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
```

存量 24 包（musl sysroot 产物，build.sh 默认指 `tmp/sysroot`）的**历史版本**
复现环境见 `docs/musl-sysroot.md` §0——不要把那个 export 块用于新移植；
存量包出**新版本**时也一律 SDK 模式（§16 2026-11-20 修订）。

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
export IOS_SYSROOT=$HOME/ios-tool/iPhoneOS10.3.sdk IOS_STUBDIR=$HOME/ios-tool
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

## 8. dynamic_lookup 链接探针恒真（2026-11-13 固化；跨包通用）

工具链链接带 `-undefined dynamic_lookup`：**链接期任何缺失符号都不报错**。
后果是 autoconf/自定义的"编译+链接"存在性探针**永远成功**——设备根本没有
的函数（glibc-ism、Linux 专有 syscall、别的包留下的声明）全部被判 yes，
错误推迟到设备运行期由 dyld 引爆（`Symbol not found` / lazy binding abort）。

- 修法两条腿：configure **后**逐个压制（`ac_cv_func_*` 缓存变量或直接
  sed config.h，见 §15.1 与 §9）+ **`tools/check-undefined.sh` 链接后
  审计门禁兜底**（§13 第 1 件工具，它就是为这坑生的）。
- 探针若带"运行"环节（`AC_RUN_IFELSE` / `ngx_feature_run=yes`），交叉
  编译下还有第二重假象：产物是 armv7 Mach-O，宿主跑不了 → 静默假阴
  （nginx 墙 #1）。**别试图让探针诚实，configure 后直接补宏。**
- 历史注：本节原为 musl 头"Linux 值穿马甲"雷区（nmap 移植），该内容
  已迁 `docs/musl-sysroot.md` §2——SDK 模式下 musl 雷区消失，但
  "Linux 专有函数被恒真探针放进 config.h"这一半跨时代依然成立，
  且多份移植文档（tor/nginx/curl/tcpdump）以"§8"引用此语义，故收敛
  为本节。

## 9. configure/autoconf 探针骗局速查（2026-11-13 nginx/mosh 沉淀；细则迁各包文档）

- **只编译不链接的探针必假阳**：声明存在 = 通过——nginx 的 setproctitle 假阳性全录 → `docs/nginx.md` §8。
- **pkg-config 不设 `PKG_CONFIG_LIBDIR` 会静默回退宿主库**：LIBDIR 是替换内置搜索路径、PATH 只是追加；交叉依赖要列全（漏一个就死在下一个 `Package not found`）→ `docs/mosh.md` §8。
- **`AC_CHECK_LIB` 的裸 `-lxxx` 交叉链接必失败**：预置 `ac_cv_lib_<lib>_<fn>=yes` 缓存变量（autoconf 官方认可的"陈述探针无法确定的事实"），再以 `*_LIBS` 链真实归档 → `docs/mosh.md` §8。
- **`AC_PATH_PROG` 只认 `$PATH`，但尊重同名环境变量**：`export PROTOC=...` 即可 → `docs/mosh.md` §8。
- **feature macro 要成组给**：`wcwidth` 等 XSI 扩展需 `-D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700`，且必须**在 configure 命令行上**（automake 把 CPPFLAGS 烘焙进 src/Makefile，`make CPPFLAGS=` 无效）→ `docs/mosh.md` §8。
- **automake 首次 make 会经 config.status 整体重写 config.h**：修正做在模板 `config.h.in`；`#ifdef` 判断的宏必须"未定义"，不能是 0 → §10 与 `docs/mosh.md` §8。

## 10. config.h 重生成陷阱（2026-11-13；根因与实录迁 `docs/mosh.md` §8）

automake 生成的 `config.h: stamp-h1` 规则会在 configure 刚跑完后的**首次 make 重跑 config.status、整体重写 config.h**——反复 sed 修好的宏又变回去就是这个。修法：改**模板** `config.h.in`（`#undef` 行改成注释保持未定义、模板缺的行追加 `#define`、`touch config.h.in` 防重生成）；**`#ifdef` 判断的宏必须"未定义"，不能是 0**（`#define HAVE_PLEDGE 0` 仍为真）。

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

### 13.1 三件防雷工具（本次固化，后续移植必须走）

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

### 13.2 桩清单（按加入原因分组）

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

### 13.3 排障时踩过的坑（本节配套）

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
- cc-wrapper 对 `-M/-MM/-MD/-MMD` **直接透传 clang**（2026-11-13 固化）。
  此前的行为（当作普通 flag 走编译+链接）会让 clang 把**依赖清单写进
  .o**（ASCII 毒化），nsock 的 makefile.dep 规则是第一个受害者。排查
  手段：`file *.o` 看见 "ASCII text" 即中毒，删掉重编。

## 14. netstat 移植（2026-11-13；自备 ABI 全录迁 `docs/netstat.md`）

自备内核 ABI（xinpgen/xinpcb/xtcpcb 偏移设备实测）、四轮探针链、编译期静态断言、输出格式——全文见 `docs/netstat.md`。此处只留一条**打包铁律**（所有 make-deb.sh 适用）：

- **deb 成员必须 gzip**：宿主新版 dpkg-deb 默认压 `control.tar.zst`/`data.tar.zst`，设备 dpkg 1.18.10 报 `unknown compression for member 'control.tar.zst'` 拒装（二进制与签名都没问题，纯容器格式）。所有 make-deb.sh 钉 `dpkg-deb --root-owner-group -Zgzip --build`。信号 → 动作：设备 `dpkg -i` 报 unknown compression → `ar t 包.deb` 看成员后缀，非 .gz 即钉 -Zgzip 重建（p7zip、lsof 同款）。

## 15. configure 交叉移植四板斧（2026-11-14，rsync/less 沉淀；实例细则迁各包文档）

1. **`ac_cv_func_*` 恒真陷阱**（§8 同源）：configure 后显式压掉已知 glibc-ism；rsync 的完整压制清单见 `docs/rsync.md`；`tools/check-undefined.sh` 门禁兜底（它就是为这坑生的）。
2. **注释禁入续行链**：`VAR=x \` 下一行以 `#` 开头 = `#` 连同行尾反斜杠一起进注释，续行断裂，**整串 env 覆盖静默失联**（rsync 一天栽两次，tor/make 同款）。规则：注释全部放赋值块上方；configure 之后 grep config.h **断言覆盖已生效**，不符即 FATAL。
3. ~~手写 sysroot 头精简版、探针假阴性~~ → musl 时代内容，迁 `docs/musl-sysroot.md` §7。
4. **git 树 ≠ 完整构建源**：rsync/less 的 git 树都缺生成物（rsync 探针在 configure.sh；less 的 funcs.h/help.c/less.hlp 只在 tarball）。信号：`No rule to make target` / 缺 .c → 换官方 release tarball；下载后先 `tar -t` 验真（sourceforge/Debian 直链给过 HTML 壳）。

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
- **musl 时代的头改写史**（kevent 运行时 ABI、Linux 值穿马甲、O_NONBLOCK
  案例与 Darwin ABI 陷阱总表）已整体迁至 `docs/musl-sysroot.md`——那是
  当年 24 包的全部代价，也是本节拍板的原始证据。

## 17. SDK 头 availability ≠ 设备现实（2026-11-15；UUID 实录迁 `docs/uuidgen.md`）

**规则：SDK 头的 availability 标注不是设备事实。**遇到"头说 iOS 没有"的函数（`__IPHONE_NA` / `__OSX_AVAILABLE` 系），先 `dlsym(RTLD_DEFAULT)` 复核符号在不在，再决定 shim/放弃，**不要按头文件宣判**。实例（内核 `gethostuuid()` 头标 `__IPHONE_NA` 设备却可用、libSystem `uuid_*` 全正常、BigBoss `uuid` CLI 死于 re-export 解析）全录见 `docs/uuidgen.md`。

## 18. FFmpeg 9.0.2 移植（2026-11-15；全录迁 `docs/ffmpeg.md` §7）

SDK 模式最大工程。两条 **wrapper 级修复**已是公共事实（固化在 cc-wrapper.sh，新移植免踩）：`-Wl,` 逗号串逐段拆分转发；`-isysroot <path>` 分立形式的路径不得漏进 CFLAGS。configure 恒真窝（SYSTEM_FUNCS 20 项）、darwin 分支四框架强制挂载、gas-preprocessor 汇编通道、lavfi 缺失等包内细节与验收全录见 `docs/ffmpeg.md` §7。

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

## 24. 设备排障四招（musl 时代反复验证的通用方法）

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
