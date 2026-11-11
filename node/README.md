<!--
node/README.pending.md — the future "Node.js" section of the main README.md.
Written in the main README's voice so it can be merged as-is once the
node/VERIFY.md checklist has actually been run. The status banner below
stays until then.
-->

## Node.js 22.23.4 (jitless)

> **Status: verified on device, 2026-11-11.** The full `node/VERIFY.md`
> checklist ran clean on the iPad 4 (iPad3,4 / P101AP, iOS 10.3.3) against
> the packaged node4 22.23.4-1: startup smoke, jitless enforcement, the
> module system (CJS + ESM + exact SHA-256 vector), buffers/timers/async-fs/
> pbkdf2 threadpool, CPU/memory reporting, an HTTP server+curl roundtrip,
> outbound plain HTTP (308 redirect as expected) and DNS resolution.
> npm is not packaged (see below).  Fourteen walls were cleared to get
> here; each is documented with its evidence chain in `node/patches/README.md`
> and the research log (private).  The one remaining known limit: this
> device cannot execute JIT-generated code at all (mprotect→RWX = SIGBUS,
> MAP_JIT = EINVAL), so running the engine without the jitless wrapper
> crashes by design — the wrapper is not optional.

Node.js 22.23.4 cross-compiled for `armv7` iOS 10.x, with an embedded V8,
libuv, OpenSSL, c-ares, zlib and llhttp statically linked into one Mach-O.
It is the first C++20 port in this repository, and the first whose hard
problem is not a kernel interface but the execution model: the target
cannot execute generated code.

### The one thing to understand: it runs jitless

V8 compiles hot JavaScript to machine code while the program runs, and
allocating executable memory for that code is what this target does not
allow — the kernel kills the process. That kill is a distinct failure mode
from the unsigned-binary kill this repo's signing rules deal with: rc=137
with empty output happens *before* `main()`; a `Killed: 9` after startup,
once code runs, is the JIT allocation. `node/VERIFY.md` item 2 is what
tells them apart.

There is nothing to configure. The `node` the package installs is a small
shell wrapper that exports `NODE_OPTIONS=--jitless` (appending to anything
the caller already set) and then `exec`s the real engine, installed next
to it as `node.real`. Running `node` always means running the wrapper;
running `node.real` directly is exactly the case that gets killed. npm and
npx, when present, are wrappers that call the jitless `node` by absolute
path so they cannot bypass it either.

Why `NODE_OPTIONS=--jitless` and nothing else — settled against the
v22.23.4 source, not assumed:

* `--jitless` has exactly one registration site, `src/node_options.cc:1068`,
  as a V8 option re-exported by Node.
* There is no `NODE_JITLESS` environment variable. The V8-side `V8_JITLESS`
  is a compile-time macro, not a runtime setting.
* `--jitless` is on the `NODE_OPTIONS` allow-list — the generated
  `doc/api/cli.md` list and the flag's own registration agree.
* `NODE_OPTIONS` is parsed before argv, and V8 has no `--no-jitless`, so
  the default cannot be switched off by spelling it differently.

What it costs: Node's own documentation says the performance impact of
`--jitless` "may be severe". No number is quoted here because none has
been measured for this build. Short scripts, file manipulation and
lightweight npm use are the intended workload. The build also omits Intl
and the startup snapshot — both deliberate, with the reasons in
`node/build.sh`.

### Building

```sh
export LD64=/path/to/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD64_LIBS=/path/to/x-libdispatch/lib:/path/to/x-tapi/lib
./node/build.sh
```

Same toolchain contract as every other build here (the clang wrapper
driving cctools `ld64`; the sysroot must be synced into `tmp/sysroot`
first, which building tmux once does). What the configure line does and
why:

| flag | why |
|---|---|
| `--dest-os=ios` | gyp's `OS` selects the dedicated `OS=="ios"` block in `common.gypi` (C++20, the macOS-Keychain opt-out, the libdispatch include path). Stated twice — here and in `GYP_DEFINES` — because gyp does not follow `--dest-cpu`/`--dest-os` |
| `--dest-cpu=arm` | 32-bit arm; the wrapper's `clang -target` emits armv7 |
| `--openssl-no-asm` | armv7 perlasm is not ABI-clean under this sysroot; the C fallback is what this repo's OpenSSL already uses |
| `--with-intl=none` | no ICU data and no ICU build; `Intl` is undefined by design |
| `--without-npm` | npm ships separately; building it in would put ~20 MB of JS in a path dpkg does not own |
| `--without-node-snapshot` | a snapshot needs a host node of the same version at build time — a bootstrap dependency this kit does not take |

`node/build.sh` is explicit about its own state: the port was driven in an
out-of-repo tree that already differs from the release tarball, and those
edits must become `node/patches/` before a clean checkout can reproduce
the build. Until then the script consumes the configured tree as-is and
says so in its output.

### Packaging and install

```sh
./node/make-deb.sh        # -> out/node4_22.23.4-1_iphoneos-arm.deb
```

Follows the repo's install convention: the kit's binaries live under
`/var/mobile/tools`, nothing under `/usr` is touched, and removing the
package leaves the device exactly as it was.

| installed file | what it is |
|---|---|
| `/var/mobile/tools/node/bin/node` | the jitless wrapper (a shell script, never signed) |
| `/var/mobile/tools/node/bin/node.real` | the engine (Mach-O, signed once on the host, asserted with `ldid -e`) |
| `/var/mobile/tools/node/lib/node_modules/` | npm's root — **currently an empty directory**: `make-deb.sh` creates it with `mkdir -p` and copies nothing into it (staging not implemented) |

`postinst` links `node` — and, once npm is staged, `npm` and `npx` — into
`/var/mobile/tools/bin` (the kit's shared bin directory) and prints the
`PATH` line. Each link is guarded by `[ -x "$BINDIR/$t" ] || continue`, so
with staging unimplemented today only `node` is linked. It deliberately
does not create `/usr/local/bin/node`; making Node answer to its bare name
is a user decision with real consequences, and *Making them the default on
a device* above applies unchanged.

npm: **not implemented.** The engine is built `--without-npm`, and
`make-deb.sh` ships no npm or npx payload at all — it creates the empty
`lib/node_modules` directory but stages nothing into it, so `postinst`'s
`[ -f "$BINDIR/npm.real" ]` test never fires and no `npm`/`npx` wrapper is
generated. The package therefore installs Node alone. The wrapper-generation
logic exists and is correct in shape (it would exec the jitless `node` by
absolute path rather than resolving `node` on `PATH`), but it stays untested
until a staging step populates `npm.real`/`npx.real` beside the engine. npm
likewise remains unverified on device — see `node/VERIFY.md`, item 7, which
also warns that npm is the most likely component to be slow rather than
broken under jitless.

### Verifying

`node/VERIFY.md` is the device checklist: ordered steps with expected
output for each. Transfer integrity first (an rc=137 with empty output is
a signature/transfer problem — check the copy before blaming the signer),
then the startup smoke, then proof that JIT really stayed off, the module
system, network, buffers and timers, CPU/memory reporting, and npm. Where
a step has a specific expected value, the checklist records the reasoning
next to it rather than a bare assertion.

### How this port differs from the others here

* **C++20.** Every other port is C against the hand-made sysroot. Node
  compiles V8 as C++20, which is why the overlay's `extern "C"` discipline
  matters, and why the link must pull in the device's own `libc++.1.dylib` —
  the LLVM-6-era runtime iOS 10.3 ships. That step is **planned, not
  implemented**: the prescan calls for a `libc++.1.tbd` in `IOS_STUBDIR`
  plus `-lc++` on the link line, but today `tools/cc-wrapper.sh` links only
  `-lSystem` and `tmp/stubs/` contains just `libSystem.tbd`. Until the stub
  and the flag are added, `std::__1` symbols from libc++ are unresolvable.
* **The sysroot overlay is load-bearing at scale.** The Mach, `libkern` and
  availability headers this port needed were added to the same overlay
  every build in this repo shares (the `dispatch/*` headers are separate —
  they come from `~/ios-tool/x-libdispatch/include`), and `node/build.sh`
  checks two sentinels from different corners of the tree so a stale sysroot
  fails loudly instead of as a compile error deep inside V8.
* **The link cannot fail; only exec can.** The final link uses
  `-undefined dynamic_lookup`, so a symbol the device does not export
  becomes a dyld error at exec, never a link error. What the device
  actually provides was therefore settled with probe programs, and the
  findings were fixed as link-time shims rather than linker flags.
