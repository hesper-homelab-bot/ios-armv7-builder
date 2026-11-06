# ios-armv7-builder

A cross-build kit for **jailbroken 32-bit iOS** (`armv7`, iOS 10.x) that works
entirely **on a Linux host** — no Xcode, no macOS, no Apple SDK, no Apple
signing.

```
Linux host ──(clang+ld64)──▶ Mach-O armv7 ──(ldid)──▶ .deb ──▶ APT repo ──▶ OTA to the device
```

What is inside:

| path | what it is |
|---|---|
| `sysroot-overlay/` | 37 headers that turn musl's Linux-ABI headers into Darwin-ABI ones — the heart of this repo |
| `tools/` | `clang`→`ld64` compiler wrapper and llvm-ar Darwin-archive helpers |
| `tmux/` | flagship build: full **tmux** (3.5a and 3.8 verified on an iPad 4) |
| `openssl/` | **OpenSSL 4.0.3** (`version`, `rand`, AES/SHA all pass on device) |
| `curl/` | **curl 8.16.0** with working HTTPS, statically linked against the above |
| `openssh/` | **OpenSSH 10.6p2** — builds, logs in, scp/sftp work; *manual use only, no daemon* |
| `tweak/nocablewarn/` | a MobileSubstrate tweak built with the same toolchain |
| `scripts/` | `.deb` packaging and self-hosted APT/Cydia repository publishing |

Upstream still supports 32-bit iOS: OpenSSL's `Configurations/15-ios.conf`
keeps the `ios-cross` target (`asm_arch armv4`) and curl has no 64-bit
assumption. Both build and run on an iPad 4 / iOS 10.3.3.

## Quick start

```sh
export LD64=/path/to/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD64_LIBS=/path/to/x-libdispatch/lib:/path/to/x-tapi/lib

(cd tmux && TMUX_VERSION=3.8 ./build.sh DEVICE=ipad)   # build tmux
./scripts/make-deb.sh                                  # sign + package
./scripts/make-repo.sh                                 # regenerate the APT repo
git add -A && git commit -m "tmux x.y" && git push     # publish (GitHub Pages)

(cd openssl && ./build.sh)      # OpenSSL 4.0.3 -> out/openssl-4.0.3-armv7
(cd curl    && ./build.sh)      # curl 8.16.0    -> out/curl-8.16.0-armv7
(cd openssh && ./build.sh)      # OpenSSH 10.6p2 -> out/openssh-*-armv7
./openssh/make-deb.sh           # openssh4 .deb, NO launchd daemon
./curl/make-deb.sh              # package both as openssl4 / curl4
```

`DEVICE` is an ssh host alias for the device; its ncurses headers and
`libncursesw.5.dylib` are pulled from it during the build.

OpenSSH is the one package here that is **not** installed as a service — see the
`OpenSSH 10.6p2` section below for how it is meant to be run.

## Install on the device

BigBoss stopped accepting new packages, so builds publish their own APT
repository (GitHub Pages, from `repo/` in this very repo):

```
https://hesper-homelab-bot.github.io/ios-armv7-builder/repo
```

Add it in Cydia/Sileo, or on the command line as root:

```sh
echo "deb https://hesper-homelab-bot.github.io/ios-armv7-builder/repo stable main" \
    > /etc/apt/sources.list.d/ios-tools.list
apt-get update
apt-get install tmux              # /usr/bin/tmux
apt-get install openssl4 curl4    # /var/mobile/openssl4, /var/mobile/tools
```

`openssl4` and `curl4` deliberately install under `/var/mobile` and never
shadow `/usr/lib/libcrypto.dylib` or `/usr/bin/curl`: the system copies are
what `sshd` and the rest of iOS are linked against, and replacing them
bricks remote access. Removing the packages (`rm -rf /var/mobile/openssl4`)
leaves the device exactly as it was.

curl needs a CA bundle for HTTPS:

```sh
export SSL_CERT_FILE=/etc/ssl/cert.pem
curl -sS https://github.com            # 200, TLS 1.2
```

Releases are also on the
[Releases page](https://github.com/hesper-homelab-bot/ios-armv7-builder/releases).

## Verified on an iPad 4 (iOS 10.3.3, armv7)

| program | result |
|---|---|
| tmux 3.8 | sessions, panes, detach/reattach, `list-windows` |
| OpenSSL 4.0.3 | `version`, `rand -hex`, `dgst -sha256`, AES-256-CBC round-trip, `speed` ≈36 MB/s AES / ≈37 MB/s SHA-256 (pure C, no asm) |
| curl 8.16.0 | `https://` to github.com / curl.se / cloudflare.com / apple.com / baidu.com — all HTTP 200, TLS 1.2 handshake ≈6 s, redirects and POST verified |
| OpenSSH 10.6p2 | real login on port 22223 with publickey auth, interactive shell, `uid=501(mobile)`; `scp` up **and** down; `sftp` `get`/`put`. Banner `SSH-2.0-OpenSSH_10.6` vs the system's `6.7`. Run by hand, never as a daemon |

TLS 1.3 is compiled in but every public test host refused it from this
device; the OpenSSL build reports the whole 1.3 suite. HTTP/2 is not
enabled (no nghttp2). `--disable-threaded-resolver` is used because
`pthread_cleanup_push`/`pop` are macro machinery on Darwin.

The one thing OpenSSH does *not* do yet is `sftp` directory listings — see the
`OpenSSH 10.6p2` section. Transfers work; `ls` output does not.

## Why this is not just `./configure && make`

Cross-compiling a POSIX program to old iOS from Linux means fighting four
separate things at once:

1. **No SDK.** There are no iOS headers on a Linux box, so a sysroot has to be
   assembled by hand. This project starts from [musl]'s headers and then
   corrects every place where the Darwin ABI differs.
2. **The Darwin ABI is not the Linux ABI.** Types, structures, signal numbers
   and even the names of `errno` and `stderr` differ. Getting one wrong gives
   you a binary that links but misbehaves at runtime.
3. **`ld64` only reads Darwin archives.** A static library produced by GNU `ar`
   is rejected outright (`archive has no table of contents`).
4. **`configure` lies when the linker is permissive.** Because undefined
   symbols are allowed (they resolve from the device at runtime), every
   `AC_CHECK_FUNCS` probe reports success — including for functions iOS does
   not have.

## The bug that hid them all: `O_NONBLOCK`

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

## The rest of the Darwin ABI traps

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
5. **Never trust a host-signed binary.** `ldid -S` on the build machine
   intermittently yields a binary the device kills with `Killed: 9` (rc 137)
   and *no crash report at all*, even though the md5 matches. Re-signing the
   same bytes on the device with its own `ldid -S` makes it run. The packaging
   scripts therefore sign twice.

## OpenSSH 10.6p2

`openssh/build.sh` builds OpenSSH portable 10.6p2 for armv7 iOS 10 on the Linux
host, linked against the `openssl/` libcrypto. It was run on the device by hand
on port 22223 (an idle port — 22 and 2222 are dropbear, 22222 is the system
OpenSSH 6.7p1, and none of them were touched) and auth, shell, scp and sftp
all worked. It is **not** installed as a service: `openssh/make-deb.sh` writes
no `/Library/LaunchDaemons` plist, nothing calls `launchctl`, and everything
lives under `/var/mobile/tools/` with an `ossh-` prefix so it can never shadow
the `ssh`/`scp` the OS itself uses. Removing the package directory leaves the
device exactly as it was.

```
remote software version OpenSSH_10.6      # vs the system's OpenSSH_6.7
```

### Why 10.6p2, and why not older

It was the first version tried and it built and ran, so no downgrade was
forced. Two things are worth recording:

* OpenSSH needs OpenSSL ≥ 1.1.1. `--with-ssl-dir` points at the OpenSSL
  **build tree** rather than an installed tree, because that version check does
  run a binary — and an armv7 binary cannot execute on the Linux host. Pointing
  at `$OSSL` (which has `lib/` but no `bin/`) makes configure fall back to
  probing the headers, which is the only thing that can work here. This is the
  "single hard blocker" `dropbear/build.sh` mentions, and this is how it is
  dodged rather than solved.
* `-DOPENSSL_API_COMPAT=0x10100000L` is passed by hand. Configure normally adds
  it itself, but only after running a probe that reports the OpenSSL version,
  and that probe cannot run here — so without the flag, OpenSSL 4 headers hide
  the 1.1-era declarations OpenSSH uses and `cipher.c` fails on
  `EVP_CIPHER_CTX_get_iv`.

No older portable release was attempted, and no survey is claimed.

### The configure lies that mattered

`openssh/ios-config.site` pins the answers. The pattern is the same one every
project in this repo hits — musl declares the function, `-undefined
dynamic_lookup` makes the link test pass, and the answer is yes for something
iOS 10 has never had. What is different about OpenSSH is that **three of the
pins cannot be found by compiling**: the binary links, and then aborts at run
time, sometimes only inside a re-exec'd child binary that starts after a
*successful* authentication. Those are marked ★ below.

| pinned | why | without it |
|---|---|---|
| `getspnam` ★ | iOS has no `/etc/shadow`; its account data is in OpenDirectory | key exchange *and* publickey auth succeed, then `sshd-session` dies with `Symbol not found: _getspnam`; the client just sees `Connection closed` |
| `setproctitle` ★ | OpenBSD-only | sshd calls it once per connection (`[accepted]`, `[session-auth early]`); the archive member that supplies it is inside `#ifndef HAVE_SETPROCTITLE`, so it is silently not compiled |
| `closefrom` ★ | iOS 10 does not export it | sshd aborts **before** binding the port, so `-t` fails and nothing listens |
| `prctl` ★ | Linux-only | `platform_disable_tracing()` runs in `sshd-session` and `sftp-server` at ordinary startup — scp and sftp break while plain ssh still works |
| `setresgid`/`setresuid` | iOS exports neither | answered **yes** on purpose: `sysroot-overlay/usr/include/unistd.h` has inline shims that forward to `setregid`/`setreuid`. Answering "no" would compile `bsd-setres_id.c`, which defines the real symbols and collides with the shims — `static declaration of 'setresgid' follows non-static declaration` |
| `freezero`, `recallocarray`, `reallocarray`, `strtonum`, `bcrypt_pbkdf`, `explicit_bzero`, `ptsname_r`, `b64_ntop`, `b64_pton`, `getexecpath`, `pledge`, `unveil`, `scan_scaled`, `fmt_scaled`, `nlist`, `readpassphrase`, `accept4`, `pipe2`, `eventfd`, `getrandom`, `memset_s` | verified absent on the device | OpenSSH's own portable fallbacks are used; two (`fmt_scaled`, `readpassphrase`) otherwise fail at compile time with undeclared identifiers |
| `login`, `logout`, `logwtmp`, `updwtmpx`, `utmpname`, `getutent` | verified absent; the `utmpx` spellings *are* present | login accounting drops to the utmpx-only path Darwin uses anyway |
| `getlastlogxbyname` | iOS exports it, but the `struct lastlogx` it fills is NetBSD's and no musl sysroot has it — and the layout cannot be measured on device | reads `ll_line`/`ll_host`/`ll_tv` off a guessed layout; answered "no", which uses the Linux-layout `struct lastlog` path that fails cleanly on a missing `/var/log/lastlog` |
| `arc4random*`, `timingsafe_bcmp`, `getentropy`, `strlcpy`/`strlcat`/`strnlen`, `asprintf`, `kqueue`, `daemon`, `initgroups`, `setrlimit`, `forkpty`/`openpty`/`posix_openpt` | verified **present** on iOS but undeclared by musl | the *headers* are fixed in `sysroot-overlay/` instead; the honest configure answer is kept |
| `innetgr` | present on iOS, and musl has no `<netgroup.h>` at all | new `sysroot-overlay/usr/include/netgroup.h` |
| `user_from_uid`, `group_from_gid`, `strmode` | present on iOS, undeclared by musl | new `grp.h` plus declarations in `pwd.h`/`string.h` |

### New Darwin ABI traps (in `sysroot-overlay/`)

| header | trap |
|---|---|
| `sys/mman.h` | **`MAP_ANON` is `0x1000` on Darwin, `0x20` in musl.** `mmap` validates its flags, so a wrong one is a *real error* rather than the silent no-op `O_NONBLOCK` was: OpenSSH's `sshkey_shield_private()` shields its host key with `mmap(..., MAP_ANON\|MAP_PRIVATE, -1, 0)` and the wrong constant made sshd refuse to start — `Unable to shield host key: Bad file descriptor`, then `no hostkeys available -- exiting`. Nothing in that message points at a header. `MAP_NORESERVE` and `MAP_STACK` were wrong too. Full Darwin `mman.h` supplied |
| `sys/stat.h` | `utimensat()`/`fchownat()` present on iOS, declared by neither musl nor OpenSSH's `bsd-misc.h` (which only declares them when it has to supply them) |
| `unistd.h` | `getentropy()`, `setlogin()`, `getlogin()` present on iOS, undeclared by musl |
| `stdlib.h` | `arc4random()` family (Darwin's CSPRNG) — and it needs `#include <stdint.h>` before it, or the declaration itself fails to parse |
| `string.h` | `timingsafe_bcmp()`, `strmode()` |
| `pwd.h`, `grp.h` | `user_from_uid()`, `group_from_gid()` |
| `netinet/in.h` | `IN_LOOPBACKNET` — the Linux name for the `127/8` leading octet; `sockaddr_is_local()` in `sshconnect.c` uses it. Darwin spells the class constants differently and never defines this name |
| `netgroup.h` | did not exist in musl at all |

### `*at()` functions accept no flags at all on iOS 10

Measured on the device by driving `fstatat`, `fchmodat`, `utimensat` and
`fchownat` with each of `{0, 0x100, 0x1000, 0x2, 0x800}`: **every call with a
non-zero flag returned `EINVAL`; every call with `0` succeeded.** musl's
`<fcntl.h>` defines no `AT_*` at all and OpenSSH only defines
`AT_SYMLINK_NOFOLLOW` in the branch where it supplies its own `utimensat()`
(which is not taken here, because iOS *has* utimensat), so the macro does not
exist on this platform and `build.sh` rewrites the three call sites to `0`.
Nothing was working before that flag existed.

### Running it

`sshd` re-execs `sshd-session` (and `sshd-auth` when privsep is on), so those
must exist next to it and be named in the config:

```
SshdSessionPath /var/mobile/tools-osshtest/ossh-sshd-session
SshdAuthPath     /var/mobile/tools-osshtest/ossh-sshd-auth
Subsystem sftp   /var/mobile/tools-osshtest/ossh-sftp-server
```

Sign **on the device** (`ldid -S` on each `ossh-*`), then run it in the
foreground so the log is readable afterwards:

```
nohup /var/mobile/tools-osshtest/ossh-sshd -D -e \
    -f /var/mobile/tools-osshtest/sshd_config > /var/mobile/tools-osshtest/sshd.log 2>&1 &
```

`ossh-sshd -t -f <config>` is the fastest way to see how far it gets.

### What did not work

* **`sftp` directory listings.** `ls` prints
  `Server sent suspect path "" during readdir of "..."` for every entry, so the
  listing body is empty. `get`, `put`, and therefore `scp` (which OpenSSH 10
  runs over SFTP) are unaffected and verified working. Not investigated
  further; the SFTP wire format this `sftp-server` emits versus what the
  OpenSSH 10 client expects is the likely place.
* **`ns_get16`/`ns_get32` stay undefined** in `sshd`/`ssh`/`ssh-keygen`
  (from OpenSSH's `getrrsetbyname.c`) and **`recvmmsg`/`sendmmsg`** in every
  binary (pulled in by `libssl-lib-ssl_lib.o`'s reference to `BIO_s_datagram`,
  which drags in OpenSSL's `libcrypto-lib-bss_dgram.o`). All six are absent on
  iOS 10. They are unreachable — `VerifyHostKeyDNS` is off and nothing in this
  build's paths calls them — and because dyld binds lazily, login/scp/sftp work
  anyway. `build.sh` prints them as notes and does not fail.
* **No password authentication, no PAM, no zlib.** `--without-*` for pam,
  libedit, selinux, libaudit, wtmpdb, ldns and zlib: no headers for any of them
  in this sysroot, and PAM would need `/etc/pam.d`, which iOS does not use.
  Compression is off, which costs nothing on a LAN.
* **`UsePrivilegeSeparation` is gone.** OpenSSH removed the directive, and
  deleting it from `sshd_config` is what makes sshd start re-exec'ing
  `sshd-session`, which in turn is what surfaced the `getspnam` crash above.

## Credits and licence

The scripts here are provided under the MIT licence. tmux, libevent and musl
keep their own licences. No Apple headers or SDK files are included: the
ncurses headers and the `libncursesw` binary are read from your own device at
build time.

[musl]: https://musl.libc.org/
[cctools-port]: https://github.com/tpoechtrager/cctools-port
