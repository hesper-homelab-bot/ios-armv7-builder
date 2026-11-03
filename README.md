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

Not working yet:

* **Exiting an attached session hangs.** `attach` works and the pane's shell is
  usable, but typing `exit` (the shell prints `logout`) leaves the client
  alive and the terminal stuck. The client stays in state `S` with an
  unreaped zombie child while the server sleeps; neither process notices the
  pane is gone.
  `SIGCHLD` handling itself is *not* the cause — a minimal test program on the
  device shows `sizeof(struct sigaction) == 12`, the handler firing and
  `waitpid` working. The suspicion is therefore tmux's
  session-destroyed → client-exit path (`server_loop`'s `exit-empty` /
  `exit-unattached` checks, and whoever is supposed to clear the client's
  session).

* `send-keys ... Enter` types the text into the pane but does not submit it
  (the pane echoes the line but never runs it). Interactive typing from a real
  terminal does work, so this seems specific to how the `Enter` key is
  delivered through the pty.

Until those are fixed, prefer `new-session -d` plus `run-shell`, and read
results from files.

### The bug that took the longest: `closefrom`

Worth recording, because it is the archetype of this whole exercise. With an
undefined-symbol-tolerant linker, `AC_CHECK_FUNCS(closefrom)` succeeds — the
symbol resolves at *link* time regardless. `closefrom()` does not exist on
iOS 10, and tmux calls it in the **forked child** right after `forkpty()`.
The result was maddening:

* the server started and looked healthy in its log
  (`spawn_pane: shell=/bin/sh`, all key bindings built);
* the session was created and then immediately destroyed
  (`hook=pane-exited`);
* every new pane died silently — no stderr, because the child's stderr goes to
  the pty it just failed to reach.

Only the crash report named it:

```
Exception Type:  EXC_CRASH (SIGABRT)
Termination Description: DYLD, Symbol not found: _closefrom
    Referenced from: /private/var/mobile/./tmux
    Expected in: dyld shared cache
```

If something aborts with no output, **read
`/var/mobile/Library/Logs/CrashReporter/*.ips` first** — it is the only channel
that survives a dyld failure.

### Other differences from a normal build

* **`errno` values.** musl's are Linux's. `EAGAIN` is 11 there and **35** on
  Darwin, so tmux's `errno != EAGAIN` tests treated every "try again" as fatal,
  and the client aborted the connection mid-handshake.
* **`SOL_SOCKET`.** Linux 1, Darwin **0xffff**. tmux hands its tty to the
  server with `sendmsg()` + `SCM_RIGHTS`; the wrong level made the kernel
  answer `EINVAL` and the client gave up.
* **`struct passwd`.** Darwin inserts `pw_change`/`pw_class`, so musl's layout
  made `pw_shell` read `pw_gecos` — tmux tried to execute a shell named
  "Mobile User".
* **`struct termios`.** musl adds `c_line`; the offsets of `c_cc`, `c_ispeed`
  and every flag differ.
* **Signal numbers and `SA_*`/`SIG_BLOCK`.** A mismatched `SIGCHLD` (Darwin 20)
  makes the client fire its child handler on unrelated events.
* Content of `sys/stat.h`, `sys/socket.h`, `sys/ioctl.h`, `bits/socket.h`,
  `bits/errno.h`, `bits/signal.h`, `errno.h`, `stdio.h`, `netdb.h`, `pwd.h`,
  `unistd.h` — see the overlay table above.

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
