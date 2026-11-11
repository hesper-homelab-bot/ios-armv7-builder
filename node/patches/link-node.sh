#!/bin/bash
# Relink the armv7/iOS node binary.
#
# Recipe notes (learned the hard way -- see PRINCIPLES.md):
#   * ALL archives must be darwin-format FLAT archives (obj.target/flatdeps/*.flat.a
#     and obj.target/tools/v8_gypfiles/*.flat.a).  ld64 it silently ignores GNU
#     thin archives.
#   * cxx-wrapper resolves relative input paths against its OWN cwd, so every
#     path below is absolute.
#   * Extra stub objects supply things the normal gyp link would provide but
#     which the interrupted build never produced (snapshot, embedded blob, and
#     the tiny ABI shims for this platform).

# Environment (set to your own paths; values are machine-specific):
NODE_TREE="${NODE_TREE:-$HOME/scratch/node-research/node-v22.23.4}"
SHIMS_DIR="${SHIMS_DIR:-$HOME/scratch/node-shims}"
set -euo pipefail

N=$NODE_TREE
R=$N/out/Release
O=$R/obj.target

export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot
export IOS_STUBDIR=$HOME/ios-tool
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib

OUT=${1:-$R/node_randfix}

# --- runtime-bootstrap variant inputs -------------------------------------
STUBS=(
  "$O/node/src/node_main.o"                # defines _main (cc-wrapper hardcodes -e _main)
  "$O/node/src/node_snapshot_stub.o"       # SnapshotBuilder::GetEmbeddedSnapshotData -> nullptr
  "$O/v8_base_without_compiler/deps/v8/src/init/setup-isolate-deserialize.o"  # DESERIALIZING delegate (standard config)
  "/tmp/c8fixed.o"                         # C-8 __atomic_is_lock_free (armv7: only <=4 bytes lock-free)
  "/tmp/at64.o"                            # REAL 64-bit atomics (device ___atomic_load_8 is a no-op)
  "/tmp/btshim.o"                          # backtrace/backtrace_symbols (device libSystem lacks them;
                                           # without it node's own fatal printer dies in dyld and
                                           # the real error text is lost)
  "$O/mksnapshot_dev/shims_arm.o"          # C-4 futimens/utimensat + C-9 ArmUsingHardFloat
                                           # NOTE: embedded-empty/snapshot-empty stubs REMOVED --
                                           # they shadow the REAL geni/{snapshot,embedded}.o in
                                           # libv8_snapshot.flat.a (archive members are only pulled
                                           # for still-undefined symbols; objects always win).
)

# --- non-V8 flat archives --------------------------------------------------
FLATDEPS=(
  "$O/flatdeps/libnode.flat.a"
  "$O/flatdeps/libopenssl.flat.a"
  "$O/flatdeps/libuv.flat.a"
  "$O/flatdeps/libcares.flat.a"
  "$O/flatdeps/libllhttp.flat.a"
  "$O/flatdeps/libuvwasi.flat.a"
  "$O/flatdeps/libnghttp2.flat.a"
  "$O/flatdeps/libada.flat.a"
  "$O/flatdeps/libsimdjson.flat.a"
  "$O/flatdeps/libsimdutf.flat.a"
  "$O/flatdeps/libbrotli.flat.a"
  "$O/flatdeps/libsqlite.flat.a"
  "$O/flatdeps/libzstd.flat.a"
  "$O/flatdeps/libzlib.flat.a"
  "$O/flatdeps/libnbytes.flat.a"
  "$O/flatdeps/libcrdtp.flat.a"
  "$O/flatdeps/libncrypto.flat.a"
  "$O/flatdeps/libhistogram.flat.a"
  "$SHIMS_DIR/libcxx-fs.a"
)

# --- V8 flat archives ------------------------------------------------------
V8=(
  "$O/tools/v8_gypfiles/libv8_base_without_compiler.flat.a"
  "$O/tools/v8_gypfiles/libv8_compiler.flat.a"
  "$O/tools/v8_gypfiles/libv8_turboshaft.flat.a"
  "$O/tools/v8_gypfiles/libv8_initializers.flat.a"
  "$O/tools/v8_gypfiles/libv8_initializers_slow.flat.a"
  "$O/tools/v8_gypfiles/libv8_libbase.flat.a"
  "$O/tools/v8_gypfiles/libv8_libplatform.flat.a"
  "$O/tools/v8_gypfiles/libv8_zlib.flat.a"
  "$O/tools/v8_gypfiles/libv8_snapshot.flat.a"
  "$O/tools/v8_gypfiles/libabseil.flat.a"
)

echo ">>> linking $OUT"
"$HOME/ios-tool/cxx-wrapper.sh" \
  -O2 -pie \
  -o "$OUT" \
  "${STUBS[@]}" "${FLATDEPS[@]}" "${V8[@]}" \
  2>&1 | grep -vE "^(ld: warning: directory not found|ld: warning: -undefined dynamic_lookup)" || true

ls -la "$OUT"
echo ">>> undefined symbol count: $(llvm-nm-21 -u "$OUT" 2>/dev/null | wc -l)"
