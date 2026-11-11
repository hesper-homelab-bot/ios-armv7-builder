# armv7/iOS Node.js port patches - wall-by-wall

Every divergence from upstream node v22.23.4 that is load-bearing, with
the wall number that motivated it (full evidence chains: BUILD-STATE.md
(a)-(ao), kept out of git - private research notes).

Numbered patches apply to a pristine node-v22.23.4 tree. shims/ and
snapshot/ are link-time inputs rather than diffs.

## Numbered patches (diff -u against pristine v22.23.4)

- 010-torque-force32bit.patch - deps/v8/src/torque/torque.cc:
  -m32 branch no longer blocked by V8_COMPRESS_POINTERS;
  force_32bit_output unconditional. Wall #13 root cause: the host x64
  toolset (which RUNS torque) baked 8-byte kSystemPointerSize-derived
  field-offset literals into the generated *-tq-csa.cc; the ILP32 target
  layout needs 4-byte. TypedArray ctor read JSArrayBuffer::bit_field at
  literal 48 vs the real +32 -> misrouted into the GSAB runtime.

- 020-kqueue-ios-armv7.patch - deps/uv/src/unix/kqueue.c:
  EV_OOBAND registration disabled (iOS 10 kqueue rejects it, EINVAL ->
  abort); uv__kqueue_delete tolerates EINVAL alongside EBADF/ENOENT
  (a never-registered fd's EV_DELETE failing is harmless).

- 030-embedded-data-finalize.patch -
  deps/v8/src/snapshot/embedded/embedded-data.cc:
  FinalizeEmbeddedCodeTargets runs BEFORE the early-dump exits (wall #12:
  the device-generated blob must carry its 11,415 builtin-to-builtin
  pc-relative fixups), plus the call1-dump/call2-exit diagnostic used to
  extract the blobs on device. The dump machinery is needed only for
  on-device snapshot regeneration; node itself never calls
  CreateSnapshotDataBlob.

- 040-kmmapfd.patch - deps/v8/src/base/platform/platform-posix.cc:
  V8 kMmapFd = VM_MAKE_TAG(255) pseudo-fd raises SIGSYS on iOS 10;
  use fd -1 (plain mmap) instead.

- 050-toolchain-host-compress.patch - tools/v8_gypfiles/toolchain.gypi:
  HOST toolset only: V8_COMPRESS_POINTERS + V8_COMPRESS_POINTERS_IN_SHARED_CAGE
  so the host torque/mksnapshot agree with the target 4-byte tagged size
  (kTaggedSize=4 via compression, host pointers stay 8).

- 060-v8gyp-torque-m32.patch - tools/v8_gypfiles/v8.gyp: pass -m32
  to torque in the run_torque action (OUTPUT mode flag selecting
  force_32bit_output; NOT a -m32 compile of torque itself). Without it
  a re-gyp regenerates the action without the flag and silently
  reintroduces wall #13. NOTE: 050 + 060 + 010 are one system - the
  host compression defines, the unconditional force_32bit_output, and
  the flag keeping generated literals at arm32 layout.

## sysroot fix (lives in ../sysroot-overlay/, wall #14)

usr/include/sys/event.h: struct kevent must be 20 bytes - the iOS
10.3.3 armv7 kernel reads the 32-bit kevent ABI with 20-byte strides and
NO ext[] tail. An ext[4] tail (52 bytes) made libuv/ares changelists
misparse from the 2nd change onward (kernel echoed ext[] bytes back as
bogus EV_ERROR{ident=0} events -> bad-fd aborts / SIGBUS). Rule: every
kernel-interacting struct in the hand-made sysroot needs a MULTI-element
runtime probe; a 1-change probe cannot detect a stride mismatch (the
first element is always aligned).

## shims/ - link-time objects (compiled by cc-wrapper/cxx-wrapper)

- at64.S - real 64-bit atomics for armv7 (LDREXD/STREXD+dmb):
  the device __atomic_load_8/libatomic is a silent no-op
  (returns garbage), which corrupted OpenSSL CSPRNG. Provides
  load/store/exchange/CAS/fetch_* for 8-byte.
- c8fixed.S - __atomic_is_lock_free: return 1 only for size <= 4
  (the generic libatomic lies that 8 is lock-free).
- btshim.c - backtrace/backtrace_symbols via frame-pointer chain:
  the device lib lacks them, and node error printing dies in dyld
  without them.
- shims.cc - ArmUsingHardFloat ABI glue, getsectiondata, and the
  libc++ fs shims companions.
- libcxx-fs-src/ - LLVM 15.0.7 libc++ <filesystem> compiled as
  libcxx-fs.a (26/26 fs symbols) because the device libc++ has no
  filesystem; needs -U_LIBCPP_NO_EXCEPTIONS on the fs TUs (the injected
  define turns __throw_filesystem_error into abort).

Link order (see link-node.sh): node_main.o, node_snapshot_stub.o,
setup-isolate-deserialize.o, shims, at64.o, btshim.o, c8fixed.o, then
the flat archives (flatdeps + libv8_* + libcxx-fs.a).

## snapshot/ - device-generated V8 blobs for the final link

See snapshot/README.md. The device CANNOT use upstream node-snapshot
machinery; the startup blob + embedded blob are generated on-device by
the fixed mksnapshot and linked as data.

## link-node.sh

The exact relink recipe (flat-archive discipline, input order, stubs).
build.sh in ../ is the from-scratch aspirational script; this is the
proven incremental path.
