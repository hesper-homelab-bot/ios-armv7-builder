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
| `openssh/` | **OpenSSH 10.6p2** — builds, logs in, ssh/scp/sftp all work (sftp directory listings included); ships the `com.hesper.osshd` daemon, defaulting to port 22 |
| `node/` | **Node.js 22.23.4** (V8 12.4) — the first full Node runtime for armv7 iOS, jitless by force of the device memory model, with a real embedded code blob + startup snapshot from a custom arm32-capable `mksnapshot` |
| `wget/` | **GNU wget 1.25.0** with HTTPS, statically linked against the OpenSSL 4 build |
| `git/` | **git 2.51.2** — the first working git for armv7 iOS; static zlib (cross-built here) + libcurl + OpenSSL; clone/fetch/push over HTTPS verified on device |
| `vim/` | **Vim 9.1** (huge, no GUI) linked against the device's own libncursesw, with the full runtime tree |
| `libpcap/` | **libpcap 1.10.5** with working live BPF capture (`/dev/bpf*` on the device); needs an XNU `net/bpf.h` that this repo now carries in `sysroot-overlay/` |
| `tcpdump/` | **tcpdump 4.99.5** — live packet capture on `en0` verified (captured real SSH traffic); needs root, Wi-Fi refuses promiscuous mode with a warning |
| `netstat/` | **netstat 1.0** — device-verified ABI (xinpgen/xinpcb/xtcpcb offsets measured on xnu-3789.70.16); `-a -t -u -r -i` all functional; 23/23 audit green |
| `sqlite/` | **sqlite3 3.54.1** (32-bit) — direct amalgamation build, no configure; WAL/FTS-capable, fully static |
| `jq/` | **jq 1.7.1** statically linked with oniguruma 6.9.10 — `test()` regex verified, UTF-8 round-trips |
| `nmap/` | **Nmap 7.95** (nmap + ncat) — the most invasive port: five bundled libraries, libdnet backend surgery, OpenSSL 4 opaque-struct patches, and a cc-wrapper fix for `-MM` dependency scanning |
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
(cd lsof    && ./build.sh)      # lsof 4.99.7    -> out/lsof-4.99.7-armv7
./openssh/make-deb.sh           # openssh4 .deb, incl. the com.hesper.osshd daemon
./curl/make-deb.sh              # package both as openssl4 / curl4
./lsof/make-deb.sh              # package lsof as the lsof .deb

(cd node && ./build.sh)         # Node 22.23.4; the load-bearing recipe is node/patches/ + docs/node.md
./node/make-deb.sh              # node4 .deb: jitless wrapper + signed binary

# ---- the 2026-11 application batch ----
./wget/make-deb.sh              # wget4 .deb (build was already in the tree)
(cd libpcap  && ./build.sh)     # libpcap 1.10.5 -> out/libpcap-1.10.5/armv7; needs gh to fetch XNU headers once
(cd tcpdump  && ./build.sh)     # tcpdump 4.99.5 (discovers ../libpcap-* itself)
./tcpdump/make-deb.sh
(cd git      && ./build.sh)     # git 2.51.2: hand-written config.mak + static zlib/curl/openssl
./git/make-deb.sh
(cd vim      && ./build.sh)     # Vim 9.1 (huge) against the device's libncursesw
./vim/make-deb.sh
(cd sqlite   && ./build.sh)     # sqlite3 3.54.1: direct amalgamation, no configure
./sqlite/make-deb.sh
(cd jq       && ./build.sh)     # jq 1.7.1 + oniguruma 6.9.10, both static
./jq/make-deb.sh
(cd nmap     && ./build.sh)     # nmap 7.95 + ncat; wall list in nmap/build.sh
./nmap/make-deb.sh
(cd netstat  && ./build.sh)     # netstat 1.0: hand-rolled from device-measured xinpgen/xinpcb/xtcpcb ABI
./netstat/make-deb.sh
```

`DEVICE` is an ssh host alias for the device; its ncurses headers and
`libncursesw.5.dylib` are pulled from it during the build.

OpenSSH is installed as a service too, on its own port (default 22) and via
its own `com.hesper.osshd` plist — it does not touch `/usr/sbin/sshd`, which the
system sshd plist names by absolute path. Installing both SSH packages means
moving one of them off 22; see *One device, one layout* for how that is handled
gracefully rather than silently.

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
apt-get install lsof              # /var/mobile/tools/lsof
apt-get install node4             # /usr/local/bin/node (jitless wrapper)
apt-get install wget4 git vim     # /var/mobile/tools/{wget,git,vim}
apt-get install sqlite3 jq tcpdump # /var/mobile/tools/{sqlite3,jq,tcpdump}
apt-get install nmap               # /var/mobile/tools/{nmap,ncat} + share/nmap
apt-get install netstat4            # /var/mobile/tools/bin/netstat
```

All seventeen packages this repository builds are in it — including `dropbear4`
and `openssh4`, which at first shipped only as
[release assets](https://github.com/hesper-homelab-bot/ios-armv7-builder/releases)
(`make-repo.sh` publishes every `out/*.deb`, and the repo now carries the two
SSH packages as well). That removes the old release-only guard, so keep the
reason it existed in mind: these are the packages that replace or shadow
system SSH components, and an `apt-get upgrade` can now update them — re-check
ports and re-load the daemon after such an upgrade. The release assets stay
up for manual installs:

```sh
dpkg -i openssh4_10.6p2-1_iphoneos-arm.deb
sudo launchctl load -w /Library/LaunchDaemons/com.hesper.osshd.plist
```

The package ships the job, the wrapper and an `sshd_config`, so an install
gives a running service on port **22** instead of a directory of binaries; host
keys are generated on first start. Re-signing on the device is no longer
needed — the packaging scripts now assert the signature rather than swallowing
the failure that caused the old warning.

`openssh/make-deb.sh` takes `OSSH_PORT=` to package it elsewhere, and
`dropbear/make-deb.sh` takes `DROPBEAR_PORT=` (plus `DROPBEAR_EXTRA_ARGS=` for
an extra `-p`) for the same reason. Both default to 22.

Which packages the repository carries is simply what `scripts/make-repo.sh`
finds under `out/` at generation time — there is no allowlist; remove a
`.deb` from `out/` before regenerating if you do not want it published.

The *libraries* stay untouched: `/usr/lib/libcrypto.dylib` and the shared
cache are what `sshd` and the rest of iOS are linked against, and replacing
them bricks remote access. Removing the packages (`rm -rf /var/mobile/openssl4`)
leaves the device exactly as it was.

### Making them the default on a device

If you want the new tools to answer to their bare names, **symlink rather than
copy** — a symlink is one `rm` from being reverted, keeps a single source of
truth, and leaves dpkg's md5sums valid, whereas a file copied into a
dpkg-owned path is silently clobbered back to 0.9.8zg by the next
`--reinstall`.

Three things that are easy to get wrong:

* A **non-login shell** (`sh -c`, scripts, launchd jobs) gets
  `PATH=/usr/bin:/bin` and cannot see `/usr/local/bin` at all, so a link placed
  only there leaves scripts on the old versions. Put links in `/usr/bin` too,
  but only for files no dpkg package owns.
* Do not `dpkg -r` the old packages. `openssh` owns `/usr/sbin/sshd` and the
  ssh clients, and `sshpass` depends on it; removing it is the one step in this
  whole exercise that can cost remote access. Shadow, do not delete.
* Never write over a dpkg-owned binary — write a symlink somewhere earlier on
  `PATH` instead.

Which links actually exist on the author's iPad, and how to undo them, is in
`DEVICE.md` (not published).


## Verified on an iPad 4 (iOS 10.3.3, armv7)

| program | result |
|---|---|
| tmux 3.8 | sessions, panes, detach/reattach, `list-windows` |
| OpenSSL 4.0.3 | `version`, `rand -hex`, `dgst -sha256`, AES-256-CBC round-trip, `speed` ≈36 MB/s AES / ≈37 MB/s SHA-256 (pure C, no asm) |
| curl 8.16.0 | `https://` to github.com / curl.se / cloudflare.com / apple.com / baidu.com — all HTTP 200, TLS 1.2 handshake ≈6 s, redirects and POST verified |
| OpenSSH 10.6p2 | runs as a LaunchDaemon with publickey auth, `scp` up **and** down, and `sftp` `get`/`put`/`ls` all working. Banner `SSH-2.0-OpenSSH_10.6` vs the system's `6.7` |
| lsof 4.99.7 | `lsof -p $$`, full enumeration (every PID, correct paths/users/pipes), `lsof -nP -i` with TCP states, `-i :port`; other users' processes with `sudo`. Replaces the 4.78 that fails with "Cannot allocate memory" on every PID |
| Node.js 22.23.4 | `node --version` → v22.23.4; `-e` JS execution; HTTP roundtrip server; curl ↔ node interop; outbound HTTP/HTTPS/DNS; ESM imports; SHA-256 known-answer vectors; `pbkdf2` on the threadpool; `os.cpus()` = P101AP × 2. JIT is impossible on this device (W^X), so the wrapper forces `--jitless` |
| wget 1.25.0 | `wget --version`; HTTPS GET to example.com returns the page body (static OpenSSL 4 + `/etc/ssl/cert.pem`) |
| git 2.51.2 | `git --version`; `init -b main` → `add` → `commit` → `log`/`status`/`fsck` all green; `clone --depth 1` over HTTPS (gitee mirror, 35 s incl. TLS) with `http.sslCAInfo` shipped in `/var/mobile/tools/etc/gitconfig`. github.com is unreachable from the test network, not from git |
| Vim 9.1 | `vim --version` (huge, `+multibyte`, no GUI); scripted edit (`-es` + `syntax` + substitute + `wq`) writes correctly; runtime found under `/var/mobile/tools/share/vim/vim91` |
| tcpdump 4.99.5 | `tcpdump --version`, `-D` lists en0/en2/awdl0/utun0; live capture `-i en0 -c 2 -n -q port 22` received packets by filter with 0 dropped (as root; Wi-Fi declines promiscuous mode with a warning) |
| sqlite3 3.54.1 | `--version` (32-bit); CREATE/INSERT/`sum()`/`PRAGMA journal_mode=wal` (real WAL on disk)/`.schema`/SELECT with WHERE all green |
| jq 1.7.1 | `--version`; `.a[1]`, `reduce range(100)`, `add` over 20000 values, `test("f..h")` regex (oniguruma), UTF-8 `café` round-trip, `sort` |
| Nmap 7.95 | `--version`; `--iflist` enumerates interfaces (lo0/en0/en2/awdl0/utun0); `-sT -n -p 22,22226 127.0.0.1` reports `22/tcp open ssh` + `22226/tcp open` in 0.17 s (data files shipped; Wi-Fi declines promiscuous mode) |
| netstat 1.0 | `-a/-t/-u/-r/-i` all pass; active TCP/ESTABLISHED/CLOSE_WAIT/LISTEN, UDP/raw, routes (`default` via en0, Expire in seconds), 13 interfaces with MAC/IPv4/IPv6/stats; cross-checked with `lsof` and `ipconfig` |

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

## Signing: once, on the host

`ldid -S` runs on the build machine and nowhere else. The old "sign twice,
on the device" rule this repo used to follow was disproved — the full
post-mortem, including the controlled experiment, is in `DEVICE.md`, which
is not published. The packaging scripts now assert the signature instead of
swallowing the failure that caused the folklore.

## One device, one layout

Which ports the daemons end up on, what else is installed on the device, and
how any of it was changed are recorded in `DEVICE.md` — a file that is in
`.gitignore` and never published. What is here is only what another user needs:
the packages default to port 22, one daemon per job, and moving one means
editing its conffile.

Two things about the layout are worth stating for anyone who installs both
packages. They cannot both own 22, and the one that loses the race refuses to
start rather than looping under `KeepAlive` with a silent exit:

```
osshd-daemon: port 22 is already in use -- not starting.
holder: /var/mobile/tools/db-dropbear -F -E -p 22 ...
```

And the plists plus `sshd_config` are **conffiles**, so the port you set is not
overwritten by the next `apt-get upgrade` — which is the difference between an
upgrade you can fix in a minute and one that quietly puts two daemons on one
port.


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

## OpenSSH 10.6p2

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

## lsof 4.99.7

lsof is the clearest illustration of why *which kernel interface a program
uses* decides whether it can be ported at all.

The lsof 4.78 that ships in jailbreak images predates the libproc era. It
parses `struct kinfo_proc` out of a `sysctl(KERN_PROC_ALL)` buffer by hand,
and the struct it was compiled against no longer matches the iOS 10 kernel —
so it runs, prints its banner, and then reports `Cannot allocate memory` for
**every** PID. Nothing is wrong with the kernel or the process table; the
program is reading the wrong bytes at the wrong offsets. There is no way to
fix that from outside, and no reason to: since 4.80 the Darwin dialect talks
to the kernel through `proc_listpids()`/`proc_pidinfo()`/`proc_pidfdinfo()` —
the same libproc interface `ps` uses — and iOS exports it.

That moves the whole port into headers, and really into one header:
`sys/proc_info.h`, which defines the `PROC_PID*` flavor numbers and the
structs the kernel copies into the caller's buffer. Those structs are kernel
ABI. A field a few bytes off does not fail to compile — it makes every
answer silently wrong, which is exactly the disease described above. So the
sysroot's copy is taken **verbatim** from the xnu tag matching the device
kernel (`uname -v` says `xnu-3789.70.16~4`, so the tag is `xnu-3789.70.16`;
the `~n` build suffix never changes the headers) — not hand-written, not
borrowed from a newer macOS SDK:

```sh
git clone --depth 1 --branch xnu-3789.70.16 --filter=blob:none --sparse \
    https://github.com/apple-oss-distributions/xnu
cd xnu && git sparse-checkout add --skip-checks bsd/sys/proc_info.h
```

`proc_info.h` drags a small tail of Darwin headers behind it; the overlay
provides minimal versions of each, field-checked against the same tag:
`sys/mount.h` (Darwin `struct statfs` — on iOS 10 the 64-bit-inode layout is
the only one), `sys/un.h` (with `sun_len`, which musl's omits), `sys/`
`kern_control.h`, `netinet/tcp_fsm.h` and `tcp_timer.h` (note: the user-space
`TCPT_*` timer indices differ from the `BSD_KERNEL_PRIVATE` ones in the same
file), `mach/port.h`, `mach/machine.h`, `uuid/uuid.h`, and a Darwin
`sys/param.h` (`MAXPATHLEN` is 1024, not musl's 4096 — `vnode_info_path`
embeds it). `libproc.h` itself now only declares functions and includes
`sys/proc_info.h`; its earlier revision hand-declared a few of those structs
and got `PROC_PIDTBSDINFO` wrong (4 where the kernel says 3) — proof that
hand-copied ABI constants are a bug waiting for a caller.

The source patches are three, all in the darwin dialect: `dlsof.h` drops the
`<rpc/*>` includes (lsof's libproc code never references XDR and iOS exports
no XDR symbols), `machine.h` stops including the host's absolute
`/usr/include/string.h` and defines `HASNORPC_H` so the portmap blocks
compile out, and Configure's unconditional `-lcurses` is removed (nothing in
the dialect calls it and iOS has no curses). Configuration is entirely
environment-driven, because lsof's `Configure` predates autoconf:
`LSOF_VSTR` is the device's `uname -r` (16.7.0 → `DARWINV=1600`, which is
exact for xnu-3789), `DARWIN_BASE=libproc`, `LSOF_INCLUDE` at the sysroot,
and `LSOF_AR`/`LSOF_RANLIB` at the Darwin ar/ranlib — GNU ar archives are
unreadable by ld64.

Two behaviours worth knowing before trusting the output:

* **Root visibility.** As an unprivileged user, lsof sees only its own
  processes; other users' fds — including root daemons and their listening
  sockets — are invisible, exactly as on macOS where lsof ships setuid. Run
  `sudo lsof` for the full picture. This is the kernel enforcing
  `proc_pidinfo`, not a build defect, so do not "fix" it with setuid.
* **Stale objects.** lsof's hand-maintained Makefiles list explicit `.o:`
  dependencies that do not include sysroot headers. After changing anything
  in the overlay, `make clean` first — a stale `print.o` from before a
  header change will link happily and then misreport address families, which
  is how the duplicate-case collisions in its family switch went unnoticed
  for one build.

## Node.js 22.23.4

`node/build.sh` and `node/make-deb.sh` build and package **Node.js 22.23.4**
(V8 12.4) — the first C++20 port in this repo, and the one that pushed the
toolchain from "compiles C programs" to "compiles a modern C++ runtime".
Ships in the APT repository and as the
[node-22.23.4 release](https://github.com/hesper-homelab-bot/ios-armv7-builder/releases/tag/node-22.23.4).

What is different about this port, one line each:

* **Jitless by necessity.** The device cannot execute generated code
  (`mprotect`→RWX raises SIGBUS, `MAP_JIT` returns `EINVAL`), so the installed
  `node` is a wrapper that appends `--jitless` and execs `node.real`.
* **A real V8 code blob and startup snapshot**, produced by a custom
  arm32-capable `mksnapshot` (11,415 relocation fixups applied before the
  blob ships).
* **The deb installs ready to run**: `/usr/local/bin/node` (the wrapper) and
  `node.real`, both `ldid -S`-signed at package time — `dpkg -i` is the whole
  install. npm is not included (`--without-npm`) and Intl is off
  (`--with-intl=none`).
* **Known limits**: no JIT (wall #15 — a device memory-model fact, not a bug),
  and the kernel-locked 1 MB main-thread stack bounds deep recursion.

The engineering log for this port is the deepest in the repo: **15 walls**,
from the silent exec SIGKILL of an unsigned Mach-O (wall #10) through a no-op
`__atomic_load_8` on the device that corrupted the OpenSSL CSPRNG (wall #11),
torque's 32-bit literal layout (wall #13) and a sysroot `struct kevent` ABI
mismatch — 52 B against the kernel's 20 B — that surfaced only as wrong
`changelist` entries (wall #14). The per-wall account, the patch set
(`node/patches/`) and the verification checklist (`node/VERIFY.md`) live in
[docs/node.md](docs/node.md).

One build-system note: Node's own build system cannot run unmodified against
this hand-made sysroot, so the load-bearing recipe is the patch set plus the
link script described in `docs/node.md`; `node/build.sh` (whose header states
its own prepared/proven status) assembles the same steps.

## mosh 1.4.0 — roaming SSH over UDP (2026-11-13)

Mosh (mobile shell) keeps a terminal session alive across roaming and
sleeping clients: one short ssh exchanges the key, then everything rides a
 UDP stream that survives IP changes and long disconnections.  On the iPad
this is the difference between Termius reconnecting from scratch on every
wake and a session that simply continues.

Device-verified end to end: `mosh-server` survives the ssh channel closing
(the one thing dropbear's pty teardown used to kill), binds its UDP socket
on the SSH_CONNECTION IPv4, and a real Termius client holds a working
session.  The wall list lives in `mosh/build.sh`; the ones that mattered:

- **release URL**: the tag is `mosh-1.4.0`, not `v1.4.0` — a wrong prefix
  returns 404, `curl -f` turns that into exit 22, and a wiped source tree
  cannot re-download
- **autoconf probes lie four different ways under cross-compilation**:
  protoc (PATH-only lookup — `export PROTOC`), OpenSSL (pkg-config silently
  answers with the HOST library — set `PKG_CONFIG_LIBDIR`), `AC_CHECK_LIB`
  (a bare `-lcrypto` cannot link — pre-seed the autoconf cache variables),
  and feature-macro pairing (wcwidth is XSI: `_XOPEN_SOURCE=700` must
  accompany `_POSIX_C_SOURCE`)
- **`config.h` regenerates on every make**; header corrections go into the
  `config.h.in` *template*, plus the autotools regen chain (aclocal /
  autoconf / autoheader) must be quashed by equalizing mtimes — otherwise
  the first make discards every fix (toolchain.md §10/§13)
- **`HAVE_PLEDGE` must be undefined, not 0**: mosh tests it with `#ifdef`,
  so even a value of 0 compiles the OpenBSD-only `pledge()` call in
- **`-DNDEBUG` must match the protobuf library** (built with NDEBUG by its
  configure default): otherwise InternalMetadata's out-of-line destructor
  is referenced but provided by no archive member, and dyld kills the
  forked server on the first message destruction
- **zlib is linked by explicit archive path** (`$ZLIB/libz.a`): the
  cc-wrapper drops `-lz` (assuming it lives in libSystem — it does not) and
  the `-L`+`-lz` search does not resolve through the wrapper chain
- **six symbols ship as graceful stubs** (`libios-compat.a`): recvmmsg /
  sendmmsg (no such syscalls in iOS 10.3.3's XNU, dragged in by OpenSSL's
  static socket helpers) and the terminfo quartet (no ncurses on iOS);
  they return ENOSYS / curses ERR instead of dying

The post-link symbol audit (`tools/check-undefined.sh`) and the
device-probe whitelist generator (`tools/probe-symbols.sh`) came out of
this port; every build now runs the audit as a gate.

## The 2026-11 application batch

Eight packages added in one sweep — wget 1.25.0, git 2.51.2, Vim 9.1,
sqlite3 3.54.1, jq 1.7.1, libpcap 1.10.5, tcpdump 4.99.5 and nmap 7.95
(+ncat).  All shipped as
[release assets](https://github.com/hesper-homelab-bot/ios-armv7-builder/releases/tag/apps-20261112)
and in the APT repo.  The per-package wall lists live in each build script;
the ones worth reading:

**git** — three walls, all now encoded in `git/build.sh`:
- building from a Linux host, git's `config.mak.uname` assumes the *target*
  is Linux and bakes in Linux-only features (sync_file_range, procfs,
  getrandom, `-Wl,-rpath`); each is overridden in a hand-written config.mak
- the cc-wrapper drops `-lz` from the link line (it assumes libSystem
  re-exports zlib — true on macOS, false on iOS 10): the static libz.a is
  put on the link line explicitly, and this repo cross-builds its first zlib
- the sysroot pthread.h shipped Apple's *documented* `PTHREAD_CANCEL_*`
  values; the iOS 10.3 kernel only accepts `{0,1}` (DISABLE is **0**, not 2)
  — probed live and fixed, with a warning comment not to "fix" it back

**tcpdump + libpcap** — the device has real `/dev/bpf*` devices, but Apple
ships no userland `<net/bpf.h>`: the sysroot now carries the XNU
(xnu-3789.70.16, the iOS 10.3 kernel) version plus the two stub headers it
needs.  tcpdump 4.99.5 has no `--with-pcap`; it discovers a sibling
`../libpcap-X.Y.Z` tree.  Its configure then #defines four `HAVE_PCAP_*`
APIs that libpcap 1.10.5 does not actually have (the link probes all pass
under `-undefined dynamic_lookup`) — tcpdump dies on the *packet path* only,
which makes the trap nasty.  config.h #undefs them, checked against the
libpcap.a symbol table.

**nmap** — the most invasive port: five bundled libraries, each with its own
problem (pcre2 needs host autoreconf and `--disable-shared`; five archives
are plain GNU ar and invisible to ld64; libdnet's route/arp/eth backends are
Linux-picked and are pointed at the BSD ones; nsock's engine table picks up
epoll from a header probe).  Two are especially reusable lessons:
- nsock's `makefile.dep` rule runs `$(CC) -MM`; the cc-wrapper used to
  forward that to a full compile+link, so clang wrote the *dependency list*
  into every scanned .o (ASCII poison, invisible until `file *.o`).  The
  wrapper now passes `-M/-MM/-MD/-MMD` through untouched.
- musl's `bits/ioctl.h` defined `_IOW`-family macros with *Linux* encoding,
  so every BSD header building ioctl numbers with them got garbage — and the
  value depended on include order.  It now includes `<sys/ioccom.h>` (BSD
  semantics), and the sysroot's `netdb.h` carries the Libinfo `NI_/AI_/EAI_`
  values (`NI_NUMERICHOST` is **2** on Darwin, not 1; with 1 the device
  returns the hostname instead of an error).

**jq** — libtool's "moved library" relink logic chokes on a DESTDIR-harvested
`libonig.la`; harvest the bare `.a` + headers into a clean directory instead.
Also: jq's `builtin.c` redirects `exp10` to Apple's `__exp10`, which musl's
math.h does not declare — probe-verified live that the symbol exists, then
declared in the sysroot.

**vim** — straightforward against the device's own libncursesw (same
mechanism as tmux); the runtime tree ships in the package.

**wget** — the build was already sitting in the tree; only the .deb was
missing.  A reminder that a working build that never got packaged helps
nobody.

Everything from this batch was verified *as the mobile user* on an iPad 4 —
which caught the `/dev/bpf*` permission issue (root-only after every boot;
the device's selfheal script now opens them up) that root-only testing had
been masking all along.

## Fetching a Darwin header without guessing

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

## Credits and licence

The scripts here are provided under the MIT licence. tmux, libevent and musl
keep their own licences. No Apple headers or SDK files are included: the
ncurses headers and the `libncursesw` binary are read from your own device at
build time.

[musl]: https://musl.libc.org/
[cctools-port]: https://github.com/tpoechtrager/cctools-port
