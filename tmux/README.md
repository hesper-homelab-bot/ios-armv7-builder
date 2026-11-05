# tmux — the flagship build

Full [tmux](https://github.com/tmux/tmux) cross-compiled for `armv7`
iOS 10.x from Linux.  Both **3.5a** and **3.8** build and pass the full
on-device acceptance (see the top-level README for the ABI traps that were
fixed along the way; only the event-backend choice below is a tmux-tree
change).

## Build

```sh
cd tmux
TMUX_VERSION=3.8 ./build.sh DEVICE=ipad    # or TMUX_VERSION=latest
```

Requires the top-level prerequisites (`LD64`, `LD64_LIBS`) and an ssh alias
for the device (`DEVICE`) — ncurses headers and `libncursesw.5.dylib` are
pulled off it.  Output lands in `../out/`.

## What build.sh does

```
build.sh
 ├─ make_sysroot      musl headers  +  ../sysroot-overlay/  → ../tmp/sysroot
 ├─ get_ncurses       scp headers and libncursesw off the device
 ├─ build_libevent    configure + patches/event-config.h + fixups
 ├─ build_tmux        configure, then patch the Makefile, then make
 └─ generate stub     collect undefined symbols → libSystem.tbd → relink
```

### The compiler wrapper

`../tools/cc-wrapper.sh` compiles with `clang` and links with `ld64`. Two
rules matter more than they look:

* **Never force `-o`.** `-c foo.c` must leave `foo.o` where autoconf expects
  it, and `-E` must write to stdout. A wrapper that always passes `-o` makes
  every single configure check report "no".
* **All undefined symbols are allowed.** They are resolved from the device's
  dylibs at runtime. `-lSystem`, `-lc`, `-lm`, `-lpthread` and `-lncurses` are
  therefore ignored; only `-levent` is linked for real.

### The `libSystem.tbd` step

The first link always succeeds (undefined symbols are fine), which gives the
list of symbols the binary needs. `build.sh` turns that list into a
`libSystem.tbd` stub and relinks. This binds those symbols to libSystem as
*two-level* references. Without it, dyld follows libSystem's re-export of
`libgcc_s.1.dylib` and aborts on iOS 10 with:

```
re-exported symbol 'unknown' not found for image libgcc_s.1.dylib
```

### Makefile fixups (`patches/fixups.sh`)

Applied after `configure`: the functions below were probed successfully by
autoconf but do not exist on iOS 10, so the bundled `compat/` implementations
are linked instead — `explicit_bzero`, `setproctitle`, `freezero`,
`getdtablecount`, `closefrom`, `imsg`, `fdforkpty` (provides `getptmfd`),
`htonll`, `ntohll`, plus the Linux/BSD process-introspection checks
(`prctl`, `SO_PEERCRED`, `PROC_PID`, `GETPEERUCRED`) and ncurses-6's
`tiparm_s`.  It also adds `-I./compat` (tmux's `compat.h` includes
`<imsg.h>`) and links the device's `libncursesw` directly.

## Event backend: kqueue really is broken with ttys

Stock tmux force-disables kqueue and poll on Darwin with the comment that they
"don't work on anything except socket file descriptors (yes, really)". On iOS
10 that is literally true, and a minimal libevent program on the device
reproduces it exactly:

| fd set contents | kqueue | poll |
|---|---|---|
| listen socket + socketpairs only | PASS | PASS |
| + a pty master registered | **FAIL — accept never fires again** | PASS |

So the build removes only upstream's `setenv("EVENT_NOKQUEUE", ...)`, letting
libevent choose **poll**, and keeps `EVENT_NOPOLL`.  (3.8 stopped setting
`EVENT_NOKQUEUE` itself; `fixups.sh` rewrites `osdep_event_init()` to force
the backend regardless of how the upstream source of the day manages it.)

## Status

Verified on an iPad 4 (iPad3,4, `armv7`, iOS 10.3.3, jailbroken), from a clean
`./build.sh` run, deployed with `ldid -S`:

| check | result |
|---|---|
| `./tmux -V` | `tmux 3.5a` and `tmux 3.8` both build and pass |
| `new-session -d "<cmd>; exec sleep 900"` | exits 0 immediately, pane command runs |
| `ls`, `list-windows`, `list-panes`, `display-message` | correct output |
| `run-shell "<cmd>"` | runs |
| `send-keys "<cmd>" C-m` / `Enter` | submits to the pane |
| `capture-pane` | correct |
| `split-window`, `new-window`, `kill-session` | work |
| `attach` (interactive) | renders, keys work |
| `exit` from an attached session | client returns cleanly |

The only difference from upstream tmux source is the **event backend choice**
(poll instead of select); everything else that matters lives in the sysroot
headers.
