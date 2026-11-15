#!/bin/bash
# Build uuidgen (e2fsprogs 1.47.2 misc/uuidgen.c) for armv7 iOS 10.3.3.
#
# Why: BigBoss 'uuid' 1.6.0-2p CLI is dead on this device -- dyld fails to
# resolve libgcc_s.1.dylib's re-export through libSystem.B (Abort trap 6,
# verified 2026-11-15, three runs).  The device's libSystem uuid_* API is
# fine (dlsym + probe verified same day): this CLI is a thin frontend over
# uuid_generate / uuid_generate_time / uuid_generate_random / uuid_unparse,
# all left undefined at link time (-undefined dynamic_lookup) and resolved
# from the device's libSystem at runtime.
#
# Source: e2fsprogs-1.47.2.tar.xz (kernel.org, tytso).  Only misc/uuidgen.c
# is compiled; uuid/uuid.h comes from the real iPhoneOS10.3.sdk.  This is
# the FIRST port under the SDK sysroot mode default (AGENTS.md rule 5,
# 2026-11-15).  Two build-time shims: a minimal config.h (no NLS; getopt
# declared by the SDK's unistd.h -- iOS SDK has no getopt.h) and a no-op
# support/nls-enable.h.
#
# Usage: ./build.sh          # output ../out/uuidgen-1.47.2-armv7 (UNSIGNED)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
E2SRC="${E2FSPROGS_SRC:-$HOME/scratch/e2fsprogs/src}"
SDK="${IOS_SDK:-$HOME/ios-tool/iPhoneOS10.3.sdk}"

[ -f "$E2SRC/misc/uuidgen.c" ] || {
	echo "missing $E2SRC/misc/uuidgen.c -- fetch e2fsprogs-1.47.2.tar.xz from" >&2
	echo "  https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v1.47.2/" >&2
	echo "  then: mkdir -p src && tar -xf e2fsprogs-1.47.2.tar.xz -C src --strip-components=1" >&2
	exit 1
}
[ -f "$SDK/usr/include/uuid/uuid.h" ] || { echo "missing SDK uuid/uuid.h under $SDK" >&2; exit 1; }

export IOS_SYSROOT="${IOS_SYSROOT:-$SDK}"
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set IOS_LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

build="$here/obj"
rm -rf "$build"
mkdir -p "$build/support"

# Minimal e2fsprogs config.h: uuidgen.c needs only HAVE_STDLIB_H.  Do NOT
# define HAVE_GETOPT_H (iOS SDK ships no getopt.h; unistd.h already
# declares getopt).
cat > "$build/config.h" <<'EOF'
#define HAVE_STDLIB_H 1
EOF

# No-op NLS shim: ENABLE_NLS stays undefined, _()/N_() pass through.
cat > "$build/support/nls-enable.h" <<'EOF'
#define _(x) (x)
#define N_(x) (x)
EOF

out="$root/out"
mkdir -p "$out"
"$root/tools/cc-wrapper.sh" -O2 -Wall \
	-I"$build" \
	-o "$out/uuidgen-1.47.2-armv7" \
	"$E2SRC/misc/uuidgen.c"

echo "Built $out/uuidgen-1.47.2-armv7 (unsigned)"
