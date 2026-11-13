#!/bin/bash
# probe-symbols.sh -- device-verify that undefined symbols resolve at launch.
#
# Reads candidate symbols (one per line, nm format with leading underscore)
# on stdin, generates a probe that takes every symbol's ADDRESS in a data
# array (forcing dyld to bind ALL of them at launch -- a missing one kills
# the probe with "Symbol not found: _X"), builds it with the cross toolchain
# (dynamic_lookup passes the link), deploys it with the usual trio and runs
# it on the device.  Symbols dyld rejects are removed and the probe repeats
# until it launches clean.  The surviving list is printed to stdout --
# feed it to tools/sysroot/device-exports/ as the device-verified whitelist.
#
# Usage:  llvm-nm-21 -u BIN | ./tools/probe-symbols.sh > verified.txt
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
DEV="${DEV:-ipad}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

candidates="$(sort -u | grep -v '^$' || true)"
[ -n "$candidates" ] || { echo "no candidate symbols on stdin" >&2; exit 1; }

build_and_run() {
    # $1 = newline-separated symbol list -> emits dyld-rejected symbol or ""
    # The probe references every symbol from a __DATA section via .long
    # relocations (raw assembler, nm-style underscored names): no C
    # declarations involved, so libc builtins (abort/calloc/ceil/...) cannot
    # collide with compiler prototypes.  Data-section relocations are
    # NON-lazy: dyld must bind every symbol at launch or abort naming it.
    local list="$1" s
    {
        echo 'asm('
        echo '".section __DATA,__probe_data\n"'
        echo '".globl _probe_tab\n"'
        echo '"_probe_tab:\n"'
        while IFS= read -r s; do
            case "$s" in dyld_*|__) continue ;; esac
            printf '  ".long %s\\n"\n' "$s"
        done <<< "$list"
        echo '".text\n"'
        echo '".globl __probe_ref\n"'
        echo '"__probe_ref:\n"'
        echo '"  bx lr\n"'
        echo ');'
        # C-level `probe_tab` == Mach-O `_probe_tab` (the Apple ABI prepends
        # one underscore).  The asm above defines Mach-O _probe_tab, so the
        # C reference must NOT carry the underscore itself -- writing
        # `extern _probe_tab[]` yields Mach-O __probe_tab, an undefined
        # symbol that dyld rejects and that the removal loop then chases
        # forever (no-progress guard below now catches that class too).
        echo 'extern unsigned long probe_tab[];'
        echo 'int main(void){ return probe_tab[0]==0xdeadbeef; }'
    } > "$WORK/probe.c"

    export IOS_SYSROOT="$root/tmp/sysroot" IOS_STUBDIR="$HOME/ios-tool"
    export IOS_LD64="${IOS_LD64:?set IOS_LD64}" \
           LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    # A failed compile must be FATAL and VISIBLE: swallowing it made the
    # missing scp payload look like "all symbols bind" (false whitelist).
    if ! "$root/tools/cc-wrapper.sh" -O0 -o "$WORK/probe" "$WORK/probe.c" \
            >"$WORK/cc.log" 2>&1; then
        echo "probe COMPILE failed; log:" >&2
        tail -20 "$WORK/cc.log" >&2
        exit 1
    fi
    if ! scp -q -o ConnectTimeout=30 "$WORK/probe" "$DEV:/var/mobile/scratch/symprobe.new" 2>"$WORK/err"; then
        echo "probe deploy failed:" >&2; cat "$WORK/err" >&2; exit 1
    fi
    if ssh -o ConnectTimeout=30 "$DEV" 'cd /var/mobile/scratch && rm -f symprobe && cp symprobe.new symprobe && chmod 755 symprobe && chown mobile:mobile symprobe && ldid -S symprobe && ./symprobe' \
            >/dev/null 2>"$WORK/err"; then
        return 0
    fi
    # dyld names the first missing symbol on stderr
    grep -oE "Symbol not found: [^ |]+" "$WORK/err" | head -1 || true
    return 1
}

survivors="$candidates"
round=0
prev_count="$(printf '%s\n' "$survivors" | wc -l)"
while :; do
    round=$((round+1))
    rejected="$(build_and_run "$survivors" || true)"
    if [ -z "$rejected" ]; then
        echo "probe round $round: all symbols bind at launch" >&2
        break
    fi
    sym="${rejected#Symbol not found: }"
    survivors="$(printf '%s\n' "$survivors" | grep -vxF "$sym" || true)"
    now_count="$(printf '%s\n' "$survivors" | wc -l)"
    echo "probe round $round: dyld rejected $sym ($now_count left)" >&2
    # No-progress guard: if the rejection is not one of OUR candidates
    # (e.g. a bug in the probe itself), removing nothing changes nothing --
    # abort instead of spinning forever (seen with a self-referencing probe).
    if [ "$now_count" -ge "$prev_count" ]; then
        echo "ABORT: rejected symbol '$sym' was not a candidate; probe bug?" >&2
        exit 1
    fi
    prev_count="$now_count"
    [ -n "$survivors" ] || { echo "ALL symbols rejected" >&2; exit 1; }
done
printf '%s\n' "$survivors"
