# musl 时代 sysroot:头改写史与 ABI 陷阱(存量 24 包的遗产)

> 定位:2026-11-06~11-15 期间,工具链用的是**手搓 musl sysroot**
> (`~/ios-armv7-builder/tmp/sysroot`,musl 头 + `sysroot-overlay/usr/include/`
> 达尔文化改写)。**2026-11-15 起(§16 拍板)新移植一律走 SDK 模式**
> (`docs/toolchain.md` §16/§23),musl sysroot 只服务**存量 24 包**
> (nginx/node/nmap 等的 build.sh 默认仍指 tmp/sysroot),不重编,
> 可复现性保留在 git。
>
> 本文收纳 musl 时代的头改写史与 ABI 陷阱——它们是当年 24 包能跑通的
> 全部代价,也是理解 §16 为什么拍板的原始证据。**新移植不要按本文操作**,
> 按工具链 §16/§23;但"Darwin 与 Linux 的 ABI 差异"事实本身永远成立,
> 写新代码时仍需知道。

## 0. 复现环境(存量 24 包)

```sh
export IOS_SYSROOT=$HOME/ios-armv7-builder/tmp/sysroot
export IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
```

## 1. sysroot 结构体的运行时 ABI(wall #14 教训,2026-11-11)

编译期能过 != 运行时 ABI 正确。sysroot 是手搓的:每个**与内核交互的
结构体**(ioctl/kevent/socket option/……)都要用**多元素探针**在设备上
验证,而不是只看编译+单元素调用。已有先例:

- `sys/event.h` struct kevent 曾带 `uint64_t ext[4]`(52B 步长),
  iOS 10.3.3 armv7 内核实际按 20B 无 ext 读——libuv/ares 的 changelist
  在第 2+ 个 change 起全错(坏 fd、EINVAL abort、SIGBUS)。
  已删 ext 并留注释(sizeof 必须 =20)。

规则:新增/修改 sysroot 头里与 syscall 相关的结构体时,
编译一个多元素探针(≥2 个元素走完整 syscall 路径)在设备上跑通
才算数。单元素探针测不出 stride 错位(第 1 个永远对齐)。

## 2. 头的"Linux 值穿马甲"雷区(nmap 移植 2026-11-12)

musl 头里凡是**数值常量**(ioctl request、netdb 的 NI_/AI_/EAI_、协议号)
都默认是 **Linux/glibc 值**,与 Darwin ABI 经常不同,且差异是静默的:

- `bits/ioctl.h` 的 `_IOW` 系宏是 Linux 编码 → 所有"用宏构造"的 BSD ioctl
  (BIOCSETIF、SIOCAIFADDR…)拿到垃圾 request code,值还随 include 顺序漂移
  (先 include ioccom.h 就对,后 include 就错——两次编译结果不同的怪象之源)。
  已改为直接 include `sys/ioccom.h`(BSD 语义)+ Darwin tty 值无条件覆盖。
- `netdb.h` 的 `NI_NUMERICHOST` Linux=1 / Darwin=2:传 1 时设备返回的是
  **主机名**(Darwin 的 1 是 NI_NOFQDN),不是错误,更阴险。EAI_* 符号也
  全不同(Darwin EAI_NONAME=8,musl=-2)。已按 Apple Libinfo 正本重写。
- 判据固化:**两次探针结果不同 → 先怀疑宏依赖 include 顺序**;打印宏的
  数值(`printf("%lx", (unsigned long)BIOCSETIF)`)比猜测快十倍。

(SDK 模式下此雷区消失——Apple 头即 Darwin 正本;但同族陷阱以新形态
回归:SDK 头是公开裁剪版,见 toolchain §23。)

## 3. O_NONBLOCK:把所有问题都藏起来的那个 bug(2026-11-19 从 README 迁入)

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

## 4. Darwin ABI 陷阱总表(2026-11-19 从 README 迁入;与 §2 互为索引)

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

## 5. libSystem 缺 compiler-rt 的通用原子

**`libSystem` is missing compiler-rt's generic atomics.** clang lowers OpenSSL's
`CRYPTO_atomic_*` on armv7 to `__atomic_load`, `__atomic_store`,
`__atomic_compare_exchange` and `__atomic_is_lock_free`, none of which iOS 10
exports. clang also refuses to let C code define them (`cannot redeclare builtin
function`, even with `-fno-builtin-<name>`), so `openssl/atomic_compat.c`
implements them under internal names with a libgcc-style lock table and
`openssl/atomic_alias.s` provides the public symbols as Mach-O long-branch
stubs (`ldr pc, [pc, #-4]`).

(此问题的最终固化方案是 `tools/shims/c8fixed.S`,见 toolchain §4;这里是
最早的分析记录。)

## 6. autoconf 链接探针恒真(dynamic_lookup 时代副作用)

**Autoconf link tests always succeed here.** Because the kit links with
`-undefined dynamic_lookup`, a `checking for eventfd... yes` is worthless: the
symbol is simply left undefined and dyld aborts at first use
(`dyld: lazy symbol binding failed: Symbol not found: _eventfd`). Every Linux-only
function a project probes for — `eventfd`, `pipe2`, `accept4`, `recvmmsg`,
`sendmmsg`, `getpass_r`, `gsasl_init` — has to be switched off by hand after
`configure` runs.

(跨 sysroot 时代仍成立的规则,固化在 toolchain §15.1 与 §13 的三件防雷工具;
本节保留 musl 时代的原始记录。)
