# 自编 OpenSSH 10.6p2（ossh）专项

> 22 端口的 dropbear 见 `docs/dropbear.md`；工具链通用规则见 `docs/toolchain.md`。

## 定位与形态

- **port 22226，验证口，非兜底**：用于在真实连接上验证自编 OpenSSH 10.6p2，
  不承担任何兜底职责（设备唯一的 sshd 是 22 的 dropbear）。
- 二进制在 `/var/mobile/tools/ossh-*`：`ossh-sshd` + `ossh-sshd-auth` /
  `ossh-sshd-session`（OpenSSH 10 的三分体形态），以及 `ossh-ssh`、`ossh-scp`、
  `ossh-sftp`、`ossh-ssh-keygen` 等客户端套件。
- 守护：`com.hesper.osshd`（RunAtLoad + KeepAlive）→
  `/var/mobile/.local/bin/osshd-daemon.sh`：首跑生成 host key 并常驻前台。
- 设备侧配置：`/var/mobile/ssh-openssh/`（`sshd_config` + `ssh_host_*_key`）。
- 构建要点：`--with-privsep-user=_sshd`（iOS 预留给 sshd 的非特权用户）——
  缺它 sshd 拒绝启动（"Privilege separation user sshd does not exist"）。
- 仓库侧：`openssh/{build.sh,ios-config.site,make-deb.sh,sshd_config,
  osshd-daemon.sh,osshd.plist}`。

## 构建坑：Blowfish 未定义符号（已修）

**现象**：11 个二进制引用 `_blf_enc` 等 **5 个 Blowfish 符号 undefined**
（全量符号审计 `tools/audit-all.sh` 发现）。

**根因**：真实实现在 `openbsd-compat/blowfish.c` 里，**Makefile 已列出该文件**，
但链接时没被解析。

**修法**（已完成）：

1. `ios-config.site` 里 **pin 三个 `ac_cv_func_Blowfish_*`=no**
2. **显式链接 `blowfish.o`**——而不是 `-lopenbsd-compat`
   （**ld64 不回扫档案**，`toolchain.md` §2 同族）

**结果**：14/14 二进制 `check-undefined` 全绿。

> **注意**：这条路径**加密私钥的 KDF 会走到**，所以是**优先重建**项，
> 不是冷路径。

## 已知问题

- 从主机连 22226 报 `Permission denied (publickey)`：ossh 侧
  authorized_keys/算法配置待查（不紧急）。

## 历史：老 OpenSSH 6.7p1 已卸载

系统自带的 OpenSSH 6.7p1（曾占 22，后让位后守 22222）已于 2026-11-10 卸载：
`/usr/sbin/sshd` 与其 LaunchDaemon 均已清除，22222 不复存在。它曾因占 22 造成
dropbear crash-loop 一整天无人发现（见 `docs/dropbear.md` 事故复盘）——**勿复活**。

## 移植与验收实录（自 README 迁入 2026-11-19）


`openssh/build.sh` builds OpenSSH portable 10.6p2 for armv7 iOS 10 on the Linux
host, linked against the `openssl/` libcrypto. It runs as the
`com.hesper.osshd` LaunchDaemon on a port you choose (default 22), from
`openssh/osshd.plist`
through `/var/mobile/.local/bin/osshd-daemon.sh`, and `openssh/make-deb.sh`
writes that plist (and only that one) into `/Library/LaunchDaemons`. Everything
lives under `/var/mobile/tools/` with an `ossh-` prefix so nothing can shadow
the system `ssh`/`scp`/`sshd`, and removing the package leaves the device as it
was.

It was brought up by hand on a spare port before anything was wired into
launchd, and the ports already in use on the device were left alone throughout;
what that layout ended up being is recorded in `DEVICE.md`, which is not
published.

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
| `dirent.h`, `bits/dirent.h` | **`struct dirent` is not musl's, and the difference is two bytes.** musl declares `off_t d_off` and `d_name[256]` after it; Darwin has no `d_off` at all and adds a `d_seekoff` cookie, so on this 64-bit-`off_t` port `d_name` lands at offset 19 while the device puts it at 21. `get`/`put` never call `readdir`, so only directory listings broke — every entry came back as `""`, which is the whole `Server sent suspect path "" during readdir` bug. Measured field-by-field on the device; see below |

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

```sh
dpkg -i openssh4_10.6p2-1_iphoneos-arm.deb
sudo launchctl load -w /Library/LaunchDaemons/com.hesper.osshd.plist
```

Signing on the device is **not** needed. The old warning that a host signature
sometimes gets killed with `Killed: 9` was wrong, and the packaging now fails
loudly instead of shipping an unsigned binary; the full post-mortem is in
`DEVICE.md` (not published).

`sshd` re-execs `sshd-session`, so that path has to be in the config, and it is
not a PATH search — these are config keys:

```
SshdSessionPath /var/mobile/tools/ossh-sshd-session
SshdAuthPath     /var/mobile/tools/ossh-sshd-auth
Subsystem sftp   /var/mobile/tools/ossh-sftp-server
```

Two different reasons sshd refuses to start, both of which cost time to tell
apart from the outside:

* `Privilege separation user sshd does not exist` — iOS has `_sshd`, not
  `sshd`. Fixed by `--with-privsep-user=_sshd` at configure time; without it
  sshd cannot run as root and therefore cannot be a LaunchDaemon at all.
* It runs fine as `mobile` and fails as root. That is the same problem seen
  from the other side.

To test by hand first rather than committing it to launchd:

```sh
nohup /var/mobile/tools/ossh-sshd -D -e \
    -f /var/mobile/ssh-openssh/sshd_config > /var/mobile/.local/osshd.log 2>&1 &
```

`ossh-sshd -t -f <config>` is the fastest way to see how far it gets. Note that
`scp` and `sftp` exec the ssh binary from `/var/mobile/tools/bin/ssh`, a path
compiled in at configure time and not a PATH search — the package ships that
link, and it has to be absolute or it dangles.

### What did not work

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

### The empty `ls`, and how the real `struct dirent` was measured

The first build of this port left `sftp` directory listings broken: every entry
produced `Server sent suspect path "" during readdir of "..."` and the listing
body was empty, while `get`/`put`/`scp` and plain `ssh` were fine. The upstream
error is a *client*-side check that the server's name is neither empty nor
contains `/`, so an empty name meant `sftp-server` itself was handing the client
empty strings out of `readdir(3)` — not a wire-format problem, and not anything
`get`/`put` touch, which is exactly why only listings broke.

The cause is the last piece of musl-that-is-not-Darwin, and it is two bytes:

| | musl's `struct dirent` | Darwin's, on the device |
|---|---|---|
| `d_ino` | `ino_t` @0 | `ino_t` @0 |
| `d_off` | `off_t` @8 | — does not exist |
| | | `d_seekoff` @8 (the directory cookie) |
| `d_reclen` | `unsigned short` @16 | `unsigned short` @16 |
| `d_type` | `unsigned char` @18 | `unsigned char` @20 |
| | | `d_namlen` @18, `unsigned short` |
| `d_name` | `char[256]` @19 | `char[]` @21 |

Because this sysroot's `ino_t` and `off_t` are both 64-bit, musl's declaration
puts `d_name` at offset **19**; the device puts it at **21**. Two bytes short,
landing on a byte that is zero in every record — so every `d_name` read through
the musl offset is `""`. Nothing about that is visible at compile or link time:
the struct is only ever a pointer the target libc fills in, and it links fine
because `-undefined dynamic_lookup` accepts anything.

The table was not read out of a header. It was measured on the device by dumping
the raw records from both `getdirentries(2)` and `readdir(3)` (byte-identical,
so `readdir()` is a pass-through) against a directory of files with known name
lengths — 1, 2, 3, 6, 7, 9, 16, 19, 22, 24, 189, 254 and 255 bytes — with every
field cross-checked:

* `d_reclen` @16 — `readdir()`'s return pointer advances by exactly this much
  from one entry to the next, for all 17 entries.
* `d_namlen` @18 — equals `strlen(d_name)` for all 17 entries, 254 and 255
  included.
* `d_type` @20 — `DT_DIR`(4) for `.` and `..`, `DT_REG`(8) for every regular
  file, `DT_LNK`(10) for a symlink.
* `d_name` @21 — the name starts here for every entry.
* `d_seekoff` @8 — `telldir()` returns its low 32 bits (1, 2, 3, … the entry's
  position), which pins both the field and its offset.
* `d_name[]` is big enough for the filesystem's own limit: a 255-byte name came
  back whole.

The binary confirms it in one instruction each. In the broken
`sftp-server`, `process_readdir` computes `d_name` with
`add.w r9, r0, #0x13`; in the fixed one, `#0x15`.

`sysroot-overlay/usr/include/dirent.h` and `bits/dirent.h` now carry the Darwin
layout, so the fix is in the overlay every build in this repo shares — anything
else that includes `<dirent.h>` (curl's `file://` listing, dropbear's `scp -r`,
OpenSSL's `OPENSSL_DIR_read`, wget) gets it on its next rebuild for free.

