#!/bin/bash
# tests/lib.sh -- device acceptance helpers, sourced by every tests/<pkg>.sh.
#
# Every case is a READ-ONLY command on the device: no writes, no service
# restarts, nothing destructive.  Connection target comes from IPAD_HOST
# (default "ipad", the ssh alias documented in DEVICE.md).
#
# Per-case output: "PASS pkg: case" / "FAIL pkg: case: detail" / "SKIP ...",
# followed by one summary line per package printed by summary().

IPAD_HOST="${IPAD_HOST:-ipad}"
SSH_OPTS="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=8}"
PASS=0; FAIL=0; SKIP=0
_DEV_UP=""

# dev_up -- probe the device once per run; subsequent calls reuse the result.
dev_up() {
    [ -n "$_DEV_UP" ] && { [ "$_DEV_UP" = yes ]; return; }
    if ssh $SSH_OPTS "$IPAD_HOST" true 2>/dev/null; then
        _DEV_UP=yes
    else
        _DEV_UP=no
        echo "device $IPAD_HOST unreachable -- cases will SKIP" >&2
    fi
    [ "$_DEV_UP" = yes ]
}

# devc <remote command> -- run on the device (stdout+stderr).
devc() {
    dev_up || return 125
    ssh $SSH_OPTS "$IPAD_HOST" "$@"
}

pass() { PASS=$((PASS+1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$*"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP %s\n' "$*"; }

# expect_rc0 <case name> <device command>
expect_rc0() {
    local case="$1" cmd="$2"
    if ! dev_up; then skip "$case (device down)"; return; fi
    if devc "$cmd" >/dev/null 2>&1; then pass "$case"; else fail "$case"; fi
}

# expect_out <case name> <device command> <expected substring>
expect_out() {
    local case="$1" cmd="$2" want="$3" out
    if ! dev_up; then skip "$case (device down)"; return; fi
    if ! out="$(devc "$cmd" 2>/dev/null)"; then
        fail "$case (command rc != 0)"; return
    fi
    case "$out" in
        *"$want"*) pass "$case" ;;
        *) fail "$case: wanted [$want] got [$(printf '%s' "$out" | head -1)]" ;;
    esac
}

# summary <pkg> -- exit 0 clean pass, 1 any fail, 2 everything skipped.
summary() {
    local pkg="$1" rc=0
    printf '== %s: pass=%d fail=%d skip=%d\n' "$pkg" "$PASS" "$FAIL" "$SKIP"
    [ "$FAIL" -gt 0 ] && rc=1
    if [ "$rc" = 0 ] && [ "$PASS" = 0 ] && [ "$SKIP" -gt 0 ]; then rc=2; fi
    exit "$rc"
}
