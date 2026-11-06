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
| `openssh/` | **OpenSSH 10.6p2** — builds, logs in, ssh/scp/sftp all work (sftp directory listings included); ships the `com.hesper.osshd` daemon on port 22226 |
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

The *libraries* stay untouched: `/usr/lib/libcrypto.dylib` and the shared
cache are what `sshd` and the rest of iOS are linked against, and replacing
them bricks remote access. Removing the packages (`rm -rf /var/mobile/openssl4`)
leaves the device exactly as it was.

### Shadowing the system binaries (2026-11-06)

The command-line *binaries* are a different story, and they were moved out of
the way with **symlinks**, never with copies and never by removing packages:

| bare name | resolves to | notes |
|---|---|---|
| `/usr/bin/curl`, `/usr/local/bin/curl` | `/var/mobile/tools/curl` | 8.16.0 |
| `/usr/bin/wget`, `/usr/local/bin/wget` | `/var/mobile/tools/wget` | iOS 10 has **no** `/usr/bin/wget` at all, so nothing was displaced |
| `/usr/local/bin/openssl` | `/var/mobile/openssl4/openssl` | 4.0.3 |
| `/usr/bin/openssl` | *left alone* | dpkg file (`openssl 0.9.8zg-13`), still 0.9.8zg by absolute path |
| `/usr/local/bin/{ssh,scp,sftp,ssh-keygen,ssh-add,ssh-agent,ssh-keyscan}` | the matching `/var/mobile/tools/ossh-*` | 10.6p2 |
| `/usr/bin/{ssh,scp,sftp}`, `/usr/sbin/sshd` | *left alone* | dpkg files (`openssh 6.7p1-13`); **no `sshd` link was created**, deliberately |

The `sshd` row is the point: the new *clients* were taken on, the new *daemon*
was not. Nothing on the device invokes `sshd` by bare name anyway — the
sshd plist hardcodes `/usr/sbin/sshd` — so not linking it keeps port 22222
behaving exactly as before, and an `apt-get install --reinstall openssh`
cannot start a second server on a port dropbear already owns.

Two consequences of taking the clients that are easy to miss:

* **scp and sftp exec a compiled-in ssh path, not a PATH search.**
  `build.sh` configures with `--prefix=/var/mobile/tools`, so bindir defaulted
  to `$PREFIX/bin` and both binaries carry the literal
  `/var/mobile/tools/bin/ssh`. The `ossh-` prefix moves the real binaries out
  of that path, so until the package also ships a `bin/ssh` link every scp and
  sftp dies with `exec: /var/mobile/tools/bin/ssh: No such file or directory`
  while `ssh` keeps working — a very confusing failure. `make-deb.sh` now
  creates the link, with an **absolute** target: a relative `ossh-ssh` resolves
  against the link's own directory and dangles.
* **OpenSSH 10 refuses the system sshd by default.** It disables `ssh-rsa`
  (SHA-1), and the 6.7p1 server on 22222 offers only `ssh-rsa`/`ssh-dss`, so a
  bare `ssh -p 22222` fails with `no matching host key type found`. Re-enabling
  it in the device's `~/.ssh/config` restores the drop-in behaviour:

  ```
  Host *
      HostKeyAlgorithms +ssh-rsa
      PubkeyAcceptedAlgorithms +ssh-rsa
  ```

  Without that block the new client reaches dropbear on 22 but not the
  legacy server on 22222 — which is precisely the asymmetry that would look
  like a broken upgrade rather than a disabled algorithm.

`make-deb.sh` also builds with `dpkg-deb --root-owner-group`: otherwise the
binaries land on the device owned by the host's build uid (1000), a user that
does not exist there. Re-sign with `ldid -S` on the device after installing.

Three decisions worth explaining:

* **Symlink, don't copy.** A symlink is one `rm` from being reverted, keeps a
  single source of truth so a rebuilt tool takes effect without a reinstall,
  and — critically — leaves dpkg's md5sums valid. A file copied into a
  dpkg-owned path gets silently clobbered back to 0.9.8zg by the next
  `apt-get install --reinstall`.
* **`/usr/bin` for curl/wget only.** A non-login shell (`sh -c`, scripts,
  launchd jobs) gets `PATH=/usr/bin:/bin` and cannot see `/usr/local/bin` at
  all, which is easy to discover only when a script mysteriously uses the old
  version. `curl` and `wget` are owned by no dpkg package, so replacing them
  costs nothing; `openssl` is a dpkg file, so it is shadowed only through
  `/usr/local/bin`, which is already ahead of `/usr/bin` on the login-shell
  PATH (and already hosts `untether-bootstrap.sh`).
* **No package was ever removed.** `dpkg -r openssh` would delete
  `/usr/sbin/sshd`, which is the daemon `sshfix` keeps alive on port 22222 and
  which `sshpass` depends on. Removing the old package is the one step in this
  whole exercise that can actually cost remote access, so the old files stay
  on disk and are simply out-ranked on `PATH`.

The displaced iOS curl is kept at
`/var/mobile/.local/etc/system-shadow-backup/curl-ios-firmware`, deliberately
mode `644` so it cannot be executed by accident. To roll the whole thing back:

```sh
# 1. the shadowing links
sudo rm -f /usr/bin/curl /usr/bin/wget \
          /usr/local/bin/{curl,wget,openssl,ssh,scp,sftp,ssh-keygen,ssh-add,ssh-agent,ssh-keyscan}

# 2. the package-provided ssh path dependency (dpkg -r openssh4 does this too)
sudo rm -rf /var/mobile/tools/bin
sudo dpkg -r openssh4

# 3. restore the displaced iOS curl
sudo cp /var/mobile/.local/etc/system-shadow-backup/curl-ios-firmware /usr/bin/curl
sudo chmod 755 /usr/bin/curl
```

Step 1 alone is enough to go back to the system versions; steps 2 and 3 only
matter if you also want the `openssh4` package and the displaced curl gone.
Note that `ssh` keeps working throughout — it falls back to `/usr/bin/ssh`,
which was never touched.

`dpkg -V openssl openssh` afterwards flags exactly one file,
`/Library/LaunchDaemons/com.openssh.sshd.plist`, which is expected — that is the
plist whose port was moved to 22222, not anything this shadowing touched.

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
| OpenSSH 10.6p2 | runs as the `com.hesper.osshd` LaunchDaemon on port **22226** with publickey auth, `scp` up **and** down, and `sftp` `get`/`put`/`ls` all working. Banner `SSH-2.0-OpenSSH_10.6` vs the system's `6.7`. Verified from the host and from the device itself |

TLS 1.3 is compiled in but every public test host refused it from this
device; the OpenSSL build reports the whole 1.3 suite. HTTP/2 is not
enabled (no nghttp2). `--disable-threaded-resolver` is used because
`pthread_cleanup_push`/`pop` are macro machinery on Darwin.

OpenSSH's `sftp` directory listings were broken by a wrong `struct dirent`
in the shared sysroot overlay until `9cabef1` — see the `OpenSSH 10.6p2`
section for the two-byte root cause and how it was measured.

## Dropbear and sftp: who provides the server, and who does not

**Dropbear provides no sftp-server.** This is easy to get wrong — it looks like
a package we simply failed to compile — but the source says otherwise, in
`src/default_options.h` right next to the two macros that govern it:

```c
#define DROPBEAR_SFTPSERVER 1
#define SFTPSERVER_PATH "/usr/libexec/sftp-server"
```

and `default_options_guard.h` spells out the intent:

> If you want to enable running an sftp server (such as the one included with
> OpenSSH), set the path below and set `DROPBEAR_SFTPSERVER`. **The sftp-server
> program is not provided by Dropbear itself.**

`find -name '*sftp*'` over the whole 2026.94 tree returns nothing. Dropbear
only gives the *path* its `svr-chansession.c` execs when a client asks for the
`sftp` subsystem. That default path is OpenSSH's, and on this device it belongs
to the `openssh` dpkg package (`dpkg -S /usr/libexec/sftp-server` → `openssh`),
which is why dropbear's sftp cannot survive removing openssh:

| transfer path | execs | survives `dpkg -r openssh`? |
|---|---|---|
| `db-scp` | `/var/mobile/tools/db-dbclient` — ours | **yes** |
| dropbear sftp subsystem | `/usr/libexec/sftp-server` — openssh's | **no** |

`db-scp` is fine because `build.sh` rewrites `DROPBEAR_PATH_SSH_PROGRAM` to our
own dbclient. Nothing rewrites `SFTPSERVER_PATH`.

### `WITH_DB_SFTPSERVER=1`: a from-scratch server, for testing only

`sftp-server/` holds a hand-written SFTP protocol version 3 server in plain C
over POSIX calls, so that dropbear's sftp can be self-contained without
depending on either openssh's binary or anything else from this repo. It is
built and shipped **only** when `build.sh` and `make-deb.sh` are given
`WITH_DB_SFTPSERVER=1`; the default — and what the package installs — does not
include it, leaving sftp on the openssh path and scp self-contained.

> **This sftp-server is for testing and evaluation only. It is not recommended
> for production use.** It is an unaudited implementation of a network
> file-access protocol — path traversal, symlink resolution and permission
> boundaries are exactly the parts that are hard to get right and that are
> hardest to test. The fact that it is useful for proving the toolchain and for
> local experiments is not the same as it being safe to expose to untrusted
> users, and it is off by default for that reason. Do not enable it on a daemon
> reachable by anyone you do not trust.

Verified with the opt-in build: protocol version 3, `ls -la` correct on regular
files, symlinks, a 240-byte filename and subdirectories; `get`/`put` round-trip
on 150 KB byte-identical (md5 compared). That is enough to show it works, and
deliberately not presented as more than that.

One implementation note worth keeping: `build.sh` rewrites `SFTPSERVER_PATH`
**in both directions**. The source tree is reused between builds (`DB_SRC`
points at a persistent directory, not a freshly extracted tarball), so without
an explicit restore a previous `WITH_DB_SFTPSERVER=1` run would leave the path
pointing at a file the default package does not install, and the failure would
only show up on the device as a subsystem that execs nothing.

## Signing: what "Killed: 9" actually meant

Every `make-deb.sh` here used to carry the same warning — *host ldid
occasionally produces a binary the device kills with "Killed: 9" and no crash
report; signing on the device always works* — and so reported to sign twice.
That warning is wrong, and it is worth recording how it was disproved because
it cost real effort for years.

First, the two claims contradict each other in this repo's own history.
`e3fd62b` ("sign with a host ldid when available") states the host-signed
binary was *verified to run on the device* and closes the pipeline host-side.
A later commit added the "Killed: 9" comment, and it was then copied verbatim
into curl's, dropbear's and openssh's packaging.

Second, on the device today `curl`, `wget` and every `db-*` binary are signed
only on the host and have never been re-signed there — their mtimes are still
the install times — and all of them run.

Third, a controlled experiment settles it. Same binary, one variable:

| state | result |
|---|---|
| unsigned | exit **137** (SIGKILL), `Killed: 9`, stdout and stderr both **empty** |
| same binary, host `ldid -S` | runs, exits normally |
| same binary, signed on device | runs, exits normally |

The symptom is real; the diagnosis was not. The mechanism is in the old
`sign()`:

```sh
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    ldid -S "$dst" 2>/dev/null || true      # <-- this
}
```

`|| true` swallows the failure. When `ldid` is missing from `PATH`, or fails,
the binary that reaches the package is **completely unsigned**, and an unsigned
Mach-O is killed by the kernel during `exec` — before `main()`, hence no
output and no crash report. It looked intermittent ("occasionally") because it
depended on that one invocation succeeding, and it looked host-specific because
the device-side step was run by a human who would have noticed a missing
`ldid`, while the host-side failure was silent.

So host signing works, and re-signing on the device buys nothing. The correct
fix is to make the failure loud rather than to work around it — check `ldid` is
available and verify the artifact carries a signature, instead of `|| true`.
Note also that `out/` artifacts straight from `build.sh` are *unsigned* by
design; signing happens on the copies `make-deb.sh` stages.

(`ldid -e` reports success on signed and unsigned files alike here, so it is
not a test for validity — executing the binary is.)

## The port layout, and who owns what

Three SSH daemons, each on its own port, none of them a replacement for
another:

| port | daemon | what it is |
|---|---|---|
| 22 | `com.hesper.dropbear` | dropbear 2026.94, cross-built here. Primary remote access |
| 22222 | `com.openssh.sshd` | the system OpenSSH 6.7p1, moved off 22 by `sshfix` and kept under its protection |
| 22226 | `com.hesper.osshd` | OpenSSH 10.6p2, cross-built here, installed from the `openssh4` package |

Port 2222 used to be a second `-p` on dropbear, kept as a verified lifeline
while the port-22 cutover was still fresh. It is gone now: with a third daemon
on 22226 the lifeline's job is done, and one listener per job is easier to
reason about. `dropbear/dropbear-daemon.plist` still accepts
`DROPBEAR_EXTRA_ARGS="-p 2222"` if a fallback is ever wanted again — the
wrapper passes it straight through, and dropbear listens on every `-p` given.

`osshd` is started by `openssh/osshd.plist` through
`/var/mobile/.local/bin/osshd-daemon.sh`, which mirrors
`dropbear/dropbear-daemon.sh` for a reason: the host keys are generated on
first run and the package does not ship them, so without a wrapper a fresh
install leaves sshd exiting immediately, which `KeepAlive` retries forever and
silently. The daemon runs as root, which is what requires
`--with-privsep-user=_sshd` — iOS reserves `_sshd` (uid 75) for exactly this,
and the OpenSSH default of looking for a user literally named `sshd` fails
with `Privilege separation user sshd does not exist`.

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

Install the package, then sign **on the device** (`ldid -S` on each `ossh-*` —
the host signature is not always honoured, and a bad signature shows up as
`Killed: 9` with no crash report):

```sh
dpkg -i openssh4_10.6p2-5_iphoneos-arm.deb
for f in /var/mobile/tools/ossh-*; do ldid -S "$f"; done
sudo launchctl load -w /Library/LaunchDaemons/com.hesper.osshd.plist
```

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

## Credits and licence

The scripts here are provided under the MIT licence. tmux, libevent and musl
keep their own licences. No Apple headers or SDK files are included: the
ncurses headers and the `libncursesw` binary are read from your own device at
build time.

[musl]: https://musl.libc.org/
[cctools-port]: https://github.com/tpoechtrager/cctools-port
