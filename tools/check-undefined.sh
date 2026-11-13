#!/bin/bash
# check-undefined.sh -- post-link undefined-symbol audit for armv7 iOS builds.
#
# The cc/cxx wrappers link with -undefined dynamic_lookup, which makes the
# link succeed even when a library is missing entirely (zlib's -lz, protobuf
# members that were compiled out by NDEBUG).  The failure only surfaces on
# the device, at launch or on first use:
#
#     dyld: Symbol not found: _uncompress ... Expected in: flat namespace
#
# This audit closes that hole at BUILD time: every undefined symbol in the
# binary must be either
#
#   1. listed in a device .tbd stub (tmp/stubs/*.tbd, $HOME/ios-tool/*.tbd)
#      -- i.e. provably provided by the device's system libraries, or
#   2. a libc++ symbol (std::__1 / operator new/delete family) -- provided
#      by the device's libc++.1.dylib by design of the cxx wrapper, or
#   3. explicitly allowed via ALLOWED_UNDEFINED (regex, env var).
#
# Anything else fails the build with the symbol list.  Usage:
#
#     tools/check-undefined.sh path/to/macho-binary
#
# Adding a port that needs a system symbol the tbd lacks: add the symbol to
# the tbd (and to the device -- verify with a runtime probe first, see
# "能力自述不可信" in the user-level rules) -- do NOT silence the audit.
set -euo pipefail

BIN="${1:?usage: check-undefined.sh <macho-binary>}"
here="$(cd "$(dirname "$0")" && pwd)"
NM="${NM:-llvm-nm-21}"

wl="$(mktemp)"; undef="$(mktemp)"; trap 'rm -f "$wl" "$undef"' EXIT

# 1. whitelist from every tbd stub + device-verified symbol lists
#    (probe-symbols.sh output lands in tools/sysroot/device-exports/)
shopt -s nullglob
for t in "$here/../tmp/stubs/"*.tbd "$HOME/ios-tool/"*.tbd \
         "$here/sysroot/device-exports/"*.txt; do
    # an empty list file makes grep exit 1 (no match) -- must not kill the
    # script under set -e
    grep -oE '\b_[A-Za-z0-9_$]+' "$t" >> "$wl" || true
done
sort -u "$wl" -o "$wl"

# 2. undefined symbols of the binary (llvm-nm -u prints bare symbol names)
"$NM" -u "$BIN" 2>/dev/null | grep -v '^ *$' | sort -u > "$undef"

# 3. every undefined must be whitelisted (tbd) or device-libc++ (by design)
bad=0; n_undef=0; n_ok=0
while IFS= read -r sym; do
    [ -n "$sym" ] || continue
    n_undef=$((n_undef+1))
    if grep -qxF "$sym" "$wl"; then n_ok=$((n_ok+1)); continue; fi
    # dyld's own lazy-binding helper: present in every dynamic Mach-O
    [ "$sym" = dyld_stub_binder ] && { n_ok=$((n_ok+1)); continue; }
    # libc++ / libc++abi: std:: namespaces (St3__1 and std::* sub-namespaces
    # such as St16invalid_argument), the __cxxabiv1 RTTI runtime (vtables are
    # mangled N10__cxxabiv1...), fundamental-type typeinfo (__ZTIc et al.),
    # operator new/delete family and __cxa_/gxx personality -- all resolved
    # from the device's libc++ at launch (the cxx wrapper's design).
    if grep -qE 'St[0-9]|cxxabiv|^__ZTISt|^__ZTSSt|^__ZTVSt|^__ZTTSt|^__ZTI[a-z]$|^__ZTS[a-z]$|^__Zdl|^__ZdaPv|^__Znwm|^__Znam|^___cxa_|^___gxx_' <<< "$sym"; then
        n_ok=$((n_ok+1)); continue
    fi
    # caller-supplied escape hatch (use sparingly, document why)
    if [ -n "${ALLOWED_UNDEFINED:-}" ] && grep -qE "$ALLOWED_UNDEFINED" <<< "$sym"; then
        n_ok=$((n_ok+1)); continue
    fi
    echo "    UNRESOLVED: $sym" >&2
    bad=$((bad+1))
done < "$undef"

if [ "$bad" -gt 0 ]; then
    echo "FAIL $BIN: $bad/$n_undef undefined symbols are not provided by any device dylib" >&2
    exit 1
fi
echo "OK $BIN: $n_undef/$n_undef undefined symbols resolve from device dylibs (tbd: $n_ok)"
