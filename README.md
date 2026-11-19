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
| `go/` | **Go 1.27.2** darwin/arm revived port (upstream dropped darwin/arm after 1.14) — a full toolchain that cross-compiles from the host **and runs `go build` on the device itself**. **Testing only**: the port passes a 10-group conformance test and builds real programs (tailcat), but it is an experimental revival — not audited for production use, single-device verified, and several syscall paths (SVC-direct zsyscalls) are known-unfinished |
| `wget/` | **GNU wget 1.25.0** with HTTPS, statically linked against the OpenSSL 4 build |
| `git/` | **git 2.51.2** — the first working git for armv7 iOS; static zlib (cross-built here) + libcurl + OpenSSL; clone/fetch/push over HTTPS verified on device |
| `vim/` | **Vim 9.1** (huge, no GUI) linked against the device's own libncursesw, with the full runtime tree |
| `libpcap/` | **libpcap 1.10.5** with working live BPF capture (`/dev/bpf*` on the device); needs an XNU `net/bpf.h` that this repo now carries in `sysroot-overlay/` |
| `tcpdump/` | **tcpdump 4.99.5** — live packet capture on `en0` verified (captured real SSH traffic); needs root, Wi-Fi refuses promiscuous mode with a warning |
| `netstat/` | **netstat 1.0** — device-verified ABI (xinpgen/xinpcb/xtcpcb offsets measured on xnu-3789.70.16); `-a -t -u -r -i` all functional; 23/23 audit green |
| `sqlite/` | **sqlite3 3.54.1** (32-bit) — direct amalgamation build, no configure; WAL/FTS-capable, fully static |
| `jq/` | **jq 1.7.1** statically linked with oniguruma 6.9.10 — `test()` regex verified, UTF-8 round-trips |
| `nmap/` | **Nmap 7.95** (nmap + ncat) — the most invasive port: five bundled libraries, libdnet backend surgery, OpenSSL 4 opaque-struct patches, and a cc-wrapper fix for `-MM` dependency scanning |
| `lsof/` | **lsof 4.99.7** — full fd enumeration on the device (replaces the preinstalled 4.78 that dies with "Cannot allocate memory" on every PID) |
| `mosh/` | **mosh 1.4.0** — roaming SSH over UDP; the first mosh on 32-bit iOS |
| `dropbear/` | **dropbear 2026.94** — the device's actual sshd (port 22, `com.hesper.dropbear`), with its self-heal wrapper |
| `sftp-server/` | standalone **OpenSSH sftp-server** for dropbear's SFTP path |
| `nginx/` | **nginx 1.31.9** — kqueue event engine + static OpenSSL 4, packaged as the `com.hesper.nginx` LaunchDaemon |
| `python3/` | **CPython 3.13.18 / 3.14.10** — the first real Python 3 on armv7 iOS (SDK-sysroot mode, with the 8-byte-atomic ABI fixes) |
| `ffmpeg/` | **FFmpeg 9.0.2** — `ffmpeg` + `ffprobe`, every codec built in, fully static; the biggest single port in this repo |
| `p7zip/` | **p7zip 17.05** (`7za`) — LZMA2/xz/AES-256 plus zstd/brotli decoding, replacing the 2007-era 4.57 the jailbreak sources ship |
| `rsync/` | **rsync 3.3.0** — delta-transfer verified (291 B moved of 2817 B on an incremental sync) |
| `make/` | **GNU make 4.4.1** — rebuild small projects on the device itself |
| `less/` | **less 668** linked against the device's own libncursesw |
| `tor/` | **tor 0.4.8.14** — fully static; all 249 undefined symbols device-verified |
| `whois/` | **whois 5.6.6** |
| `class-dump/` | **class-dump 3.5.2** (nygard fork) — dumps ObjC classes/ivars/properties/methods out of device binaries |
| `uuid/` | **uuidgen 1.47.2** (from e2fsprogs `misc/uuidgen.c`) replacing BigBoss's uuid |
| `tailcat/` | **tailcat 0.7.0** — a WireGuard data-plane tool, the first complete Go program on this target (built with the `go/` toolchain) |
| `tweak/nocablewarn/` | a MobileSubstrate tweak built with the same toolchain |
| `scripts/` | `.deb` packaging and self-hosted APT/Cydia repository publishing |

Upstream still supports 32-bit iOS: OpenSSL's `Configurations/15-ios.conf`
keeps the `ios-cross` target (`asm_arch armv4`) and curl has no 64-bit
assumption. Both build and run on an iPad 4 / iOS 10.3.3.

## Quick start

```sh
export LD64=/path/to/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD64_LIBS=/path/to/x-libdispatch/lib:/path/to/x-tapi/lib

(cd tmux && TMUX_VERSION=3.8 ./build.sh DEVICE=<device>)   # build tmux
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

(cd go && ./build.sh)           # Go 1.27.2 darwin/arm: host cross toolchain + on-device toolchain tgz
./go/make-deb.sh                # go4 .deb: run `go build` on the iPad itself (TESTING ONLY — experimental port, see docs/go.md)

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
| nginx 1.31.9 | host-side curl `GET 200 (896 B in 8 ms)` + `HEAD 200`; `check-undefined` 233/233 symbols resolve; runs under the `com.hesper.nginx` LaunchDaemon (left stopped to save power); upgrade from 1.26.3-5 in place with device-ldid re-sign |
| mosh 1.4.0 | end-to-end device verification complete (`mosh_1.4.0-4`); the 64-bit-atomic shims (`at64.o`/`c8fixed.o`) stay linked defensively |
| FFmpeg 9.0.2 | `-version`; h264 decode → mpeg4 encode transcode on the device as `mobile` |
| python3 3.13.18 / 3.14.10 | fresh-deb acceptance as `mobile`: `print(42)`, `math.pi`, zlib, SHA-256, json/base64, file IO, tempfile/decimal, `os.uname()` → Darwin 16.7.0; 3.14.10 fixes the socket SIGBUS (8-byte atomic alignment) |
| p7zip 17.05 | device acceptance 2026-11-14: extracts LZMA2/xz archives the preinstalled 4.57 refuses |
| rsync 3.3.0 | incremental sync moves only the delta (291 B of 2817 B) |
| make 4.4.1 | runs on the device; used for on-device rebuilds |
| less 668 | paging smoke test on the device |
| tor 0.4.8.14 | `--version` / `--verify-config` pass; all 249 undefined symbols bound on the device |
| whois 5.6.6 | live whois query from the device |
| class-dump 3.5.2 | dissects a deployed ObjC test binary into full class/ivar/property/method tables |
| uuidgen 1.47.2 | prints v4 UUIDs on the device (e2fsprogs-derived) |
| tailcat 0.7.0 | `help`/`genkey`/`serve` verified on device; the Go `complex` conformance binary passes 10/10 groups — built by the on-device Go toolchain itself |
| dropbear 2026.94 | the device's production sshd on port 22 since 2026-11-10, with the v2.1 self-heal wrapper |

TLS 1.3 is compiled in but every public test host refused it from this
device; the OpenSSL build reports the whole 1.3 suite. HTTP/2 is not
enabled (no nghttp2). `--disable-threaded-resolver` is used because
`pthread_cleanup_push`/`pop` are macro machinery on Darwin.

OpenSSH's `sftp` directory listings were broken by a wrong `struct dirent`
in the shared sysroot overlay until `9cabef1` — see `docs/openssh.md`
for the two-byte root cause and how it was measured.

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

## How the ports are documented

Every ported package has its own `docs/<pkg>.md` (status, usage, traps →
fixes), and `docs/toolchain.md` collects the toolchain-level rules that
apply across packages.  The long-form porting narratives that used to live
in this README have moved there:

- the `O_NONBLOCK` bug and the Darwin ABI trap tables → `docs/toolchain.md` §20–§21
- the Darwin header fetching workflow (`tools/fetch-darwin-header.sh`) → `docs/toolchain.md` §22
- OpenSSH 10.6p2 build/verification record → `docs/openssh.md`
- lsof 4.99.7 record → `docs/lsof.md`
- Node.js 22.23.4 overview → `docs/node.md`
- mosh 1.4.0 record → `docs/mosh.md`
- the 2026-11 application batch overview → `docs/apps-202611.md`

## Credits and licence

The scripts here are provided under the MIT licence. tmux, libevent and musl
keep their own licences. No Apple headers or SDK files are included: the
ncurses headers and the `libncursesw` binary are read from your own device at
build time.

[musl]: https://musl.libc.org/
[cctools-port]: https://github.com/tpoechtrager/cctools-port
