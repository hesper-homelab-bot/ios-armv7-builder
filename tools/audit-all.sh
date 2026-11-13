#!/bin/bash
# audit-all.sh -- run the undefined-symbol audit across every shipped binary
# (out/ raw builds + binaries extracted from the APT repo debs), collecting
# per-binary results and the union of unresolved symbols for
# tools/probe-symbols.sh.
#
# Usage: tools/audit-all.sh [--update-whitelist]
#   without the flag: report only.
#   with the flag: probe the unresolved union on the device, merge survivors
#   into tools/sysroot/device-exports/, re-audit, and print the residual.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
UPDATE=0
[ "${1:-}" = "--update-whitelist" ] && UPDATE=1

RESULT="$(mktemp -d)"
trap 'rm -rf "$RESULT"' EXIT

# every binary we ship: raw builds in out/ plus deb payload binaries
binaries=()
for b in "$root"/out/*-armv7 "$root"/out/*-armv7-*; do
    [ -f "$b" ] && binaries+=("$b")
done
while IFS= read -r f; do
        # only check Mach-O executables (skip shell scripts, text files, etc.)
        file -b "$f" 2>/dev/null | grep -q "Mach-O" && binaries+=("$f")
    done < <(
    find /tmp/audit-hist -type f \( -name git -o -name sqlite3 -o -name node \
        -o -name node.real -o -name wget -o -name tmux -o -name tcpdump \
        -o -name openssl -o -name vim -o -name xxd \) 2>/dev/null)

: > "$RESULT/union.txt"
for b in "${binaries[@]}"; do
    name="$(basename "$b")"
    if out="$("$here/check-undefined.sh" "$b" 2>&1)"; then
        printf 'OK   %s\n' "$name"
    else
        printf 'FAIL %s\n' "$name"
        printf '%s\n' "$out" | grep UNRESOLVED | sed 's/ *UNRESOLVED: //' \
            | tee "$RESULT/${name}.unresolved" >> "$RESULT/union.txt"
    fi
done

sort -u -o "$RESULT/union.txt" "$RESULT/union.txt"
n_undef="$(wc -l < "$RESULT/union.txt")"
echo "----"
echo "unresolved union: $n_undef symbols (in $RESULT/union.txt)"

if [ "$UPDATE" = 1 ] && [ "$n_undef" -gt 0 ]; then
    echo "probing unresolved union on the device..."
    verified="$("$here/probe-symbols.sh" < "$RESULT/union.txt")" || {
        echo "probe failed" >&2; exit 1; }
    wl="$root/tools/sysroot/device-exports/ios-10.3.3-armv7-verified.txt"
    cat "$RESULT/union.txt" "$verified" 2>/dev/null | sort -u > "$RESULT/merged"
    # keep only symbols the device actually accepted
    comm -12 "$RESULT/merged" <(sort -u <<< "$verified") > "$wl.tmp"
    cat "$wl" >> "$wl.tmp"; sort -u "$wl.tmp" -o "$wl"; rm -f "$wl.tmp"
    echo "whitelist now $(wc -l < "$wl") symbols"
    echo "---- re-audit ----"
    for b in "${binaries[@]}"; do
        "$here/check-undefined.sh" "$b" 2>&1 | grep -E '^(OK|FAIL)' || true
    done
fi
