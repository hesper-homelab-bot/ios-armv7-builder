# ios-tmux-builder

Build **tmux** for a jailbroken **32-bit iOS** device (`armv7`, iOS 10.x) on a
**Linux host**, with no Xcode, no macOS and no iOS SDK.

The output is a Mach-O `armv7` executable whose minimum OS is `10.3`, linked
against the device's own `libSystem` and its shipped `libncursesw`.

```console
$ ./build.sh                     # newest tmux release
$ TMUX_VERSION=3.5a ./build.sh   # a pinned one
```

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

## Requirements

| | |
|---|---|
| Host | Linux (tested on Ubuntu 26.04, x86_64) |
| Compiler | `clang` that can target `armv7-apple-ios10.3` (any recent LLVM) |
| Linker | [cctools-port]'s `ld64` (`x86_64-apple-darwin*-ld`), plus its `libdispatch`/`libtapi` on `LD_LIBRARY_PATH` |
| Archiver | `llvm-ar` (must be able to write `--format=darwin`) |
| Device | a jailbroken 32-bit iOS device reachable over SSH — its ncurses headers and `libncursesw.5.dylib` are copied off it |

```sh
export LD64=/path/to/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD64_LIBS=/path/to/x-libdispatch/lib:/path/to/x-tapi/lib
./build.sh DEVICE=ipad        # DEVICE is an ssh host alias for the device
```

## Installing the result

The binary must be signed, or iOS kills it on launch:

```sh
scp out/tmux-3.5a-armv7 root@<ipad>:/var/mobile/tmux
ssh root@<ipad> 'chmod +x /var/mobile/tmux && ldid -S /var/mobile/tmux'
ssh root@<ipad> '/var/mobile/tmux -V'
```

## How it works

```
build.sh
 ├─ make_sysroot      musl headers  +  sysroot-overlay/   → tmp/sysroot
 ├─ get_ncurses……     scp headers and libncursesw off the device
 ├─ build_libevent    configure + patches/event-config.h + fixups
 ├─ build_tmux        configure, then patch the Makefile, then make
 └─ generate stub     collect undefined symbols → libSystem.tbd → relink
```

### The sysroot overlay

`sysroot-overlay/usr/include/` contains every header that had to be corrected.
The interesting ones:

| file | what had to change |
|---|---|
| `bits/alltypes.h` | `size_t`/`ssize_t`/`ptrdiff_t`/`wchar_t` from the compiler builtins; `time_t` and `suseconds_t` are 32-bit `long`; `_REDIR_TIME64` off; `sigset_t` is 32-bit |
| `sys/stat.h` | Darwin's `struct stat` layout |
| `signal.h` | Darwin's `struct sigaction` (no `sa_restorer`), `sys_signame` |
| `bits/signal.h` | Darwin signal numbers and `SA_*` / `SIG_BLOCK` values |
| `errno.h` | `errno` is `(*__error())`, not `__errno_location()` |
| `stdio.h` | `stdin`/`stdout`/`stderr` are `__stdinp`/`__stdoutp`/`__stderrp` |
| `sys/event.h` | the whole kqueue interface (Darwin layout, including `ext[4]`) |
| `libproc.h`, `mach/mach.h`, `Availability.h` | minimal stubs for the Darwin-only APIs tmux touches |
| `unistd.h`, `netdb.h`, `netinet/*`, `fcntl.h` | missing declarations and network types |

### The compiler wrapper

`tools/cc-wrapper.sh` compiles with `clang` and links with `ld64`. Two rules
matter more than they look:

* **Never force `-o`.** `-c foo.c` must leave `foo.o` where autoconf expects it,
  and `-E` must write to stdout. A wrapper that always passes `-o` makes every
  single configure check report "no".
* **All undefined symbols are allowed.** They are resolved from the device's
  dylibs at runtime. `-lSystem`, `-lc`, `-lm`, `-lpthread` and `-lncurses` are
  therefore ignored; only `-levent` is linked for real.

### The `libSystem.tbd` step

The first link always succeeds (undefined symbols are fine), which gives us the
list of symbols the binary needs. `build.sh` turns that list into a
`libSystem.tbd` stub and relinks. This binds those symbols to libSystem as
*two-level* references. Without it, dyld follows libSystem's re-export of
`libgcc_s.1.dylib` and aborts on iOS 10 with:

```
re-exported symbol 'unknown' not found for image libgcc_s.1.dylib
```

### tmux Makefile fixups

`patches/fixups.sh` applies these after `configure`, all for the reason in
point 4 above — the functions were probed successfully but do not exist on
iOS 10, so the project's own bundled implementations are used instead:

`explicit_bzero`, `setproctitle`, `freezero`, `getdtablecount`, `imsg`,
`fdforkpty` (provides `getptmfd`), `htonll`, `ntohll`

It also adds `-I./compat` (tmux's `compat.h` includes `<imsg.h>`), and links the
device's `libncursesw` directly.

## Status

Cross-compiling succeeds and **tmux works on the device**. Verified on an
iPad 4 (iPad3,4, `armv7`, iOS 10.3.3, jailbroken) with a clean build:

| check | result |
|---|---|
| `./tmux -V` | `tmux 3.5a` |
| `new-session -d -s demo "<cmd>; exec sleep 900"` | pane command ran (output file written) |
| `has-session` | exit code 0 while the server is up |
| process tree | `tmux` server owning the pane's `sleep` child |
| `run-shell "<cmd>"` | command ran (output file written) |
| socket | `/private/var/tmp/tmux-501/default` created |
| output of `build.sh` | valid `Mach-O armv7`, `NOUNDEFS\|TWOLEVEL\|PIE`, links libSystem + libncursesw |

Also verified after those fixes: `list-windows`, `list-panes`,
`display-message`, `split-window`, `capture-pane` and interactive `attach`.

### Event delivery on iOS 10

The last two faults to fall were both in libevent's event delivery, and both
were pinned down by running a *minimal* libevent program on the device and
comparing it with tmux.

**`select()` loses wakeups.** Stock tmux forces the select backend on Darwin
(`EVENT_NOKQUEUE`/`EVENT_NOPOLL`). On iOS 10 a peer's pending data does not
make `EV_READ` fire, so a client's `MSG_COMMAND` is read only by luck and
`MSG_EXIT` is never seen. The minimal program disagreed with tmux in exactly
one way — it had not set `EVENT_NOKQUEUE`, so libevent chose kqueue:

```
backend: kqueue
wrote 4 bytes BEFORE dispatch
EVENT #1 what=2 read=4        <- fired for data queued before the loop started
FINAL fired=2 (expect 2)
```

Dropping `EVENT_NOKQUEUE` fixes that class of hang. (`poll` stays disabled.)

**`EV_WRITE` is never reported**, on either backend. tmux's `proc_send()` only
queues a message and lets the event loop flush it, so `MSG_EXIT` was never
written at all. `patches/fixups.sh` now flushes synchronously in `proc_send()`;
whatever does not fit stays queued as before.

With both changes applied, the client that starts the server no longer hangs:

```
$ ./tmux -L t new-session -d -s main "echo H1 > /tmp/fin1.txt; exec sleep 900"
new-session rc : 0            <- returned immediately instead of being killed
pane ran       : H1
```

### Current trade-off (pick your poison)

The two backends fail in opposite ways, and neither is complete:

| | client that starts the server | later clients (`ls`, `list-windows`) |
|---|---|---|
| **select** (stock tmux) | hangs forever | work |
| **kqueue** (this build) | returns immediately | connect but are never served |

kqueue is what the shipped binary uses, because the hang on the first client is
the more damaging of the two — it is what makes `new-session` and typing `exit`
appear to freeze. Query commands against a running server are the outstanding
problem.

Both faults smell like the same underlying defect: **libevent never reports
`EV_WRITE` on this target** (verified on both backends), and its readiness
notifications are unreliable in general. Making `proc_send()` flush
synchronously papers over the `EV_WRITE` half, and the values in
`sysroot-overlay/usr/include/sys/event.h`, `bits/socket.h` and `bits/errno.h`
have all been checked against Darwin, so the next suspect is libevent's own
`kqueue.c`/`select.c` under this ABI rather than another missing constant.

Concretely, for a later client the server logs no `new client` at all: the
connection is established (the client logs `add peer` and sends its command) but
the listening socket's `EV_READ` never fires again. Accepting in a loop until
`EAGAIN` (`fixups.sh`) does not change it, which points at event registration
rather than at the backlog.

### Not working yet

* commands against an already-running server (`ls`, `list-windows`, `run-shell`)
  return nothing, so the second client still hangs;
* `send-keys ... Enter` types text into a pane but does not submit it.
## Repository layout

```
build.sh                  entry point
tools/cc-wrapper.sh       clang+ld64 driver
tools/darwin-ar           llvm-ar --format=darwin wrappers
patches/event-config.h    libevent configuration for this target
patches/fixups.sh         idempotent source/Makefile fixups
sysroot-overlay/          the Darwin-ABI headers
```

## Credits and licence

The scripts here are provided under the MIT licence. tmux, libevent and musl
keep their own licences. No Apple headers or SDK files are included: the
ncurses headers and the `libncursesw` binary are read from your own device at
build time.

[musl]: https://musl.libc.org/
[cctools-port]: https://github.com/tpoechtrager/cctools-port
