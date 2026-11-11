#!/bin/bash
# node/jitless-wrap.sh -- the real `node` on the device.
#
# This is the *source* of the wrapper; make-deb.sh installs a copy of it as
# /var/mobile/tools/node/bin/node (mode 0755) with the engine next to it as
# /var/mobile/tools/node/bin/node.real.  Running it directly from this repo
# does nothing useful on the host.
#
# ---------------------------------------------------------------------------
# WHY A WRAPPER AT ALL
# ---------------------------------------------------------------------------
#
# V8 allocates executable memory for its JIT at runtime.  On this device
# (armv7 iPad 4, iOS 10.3.3) that allocation is fatal: the kernel kills the
# process.  The exact kill is a property of the device, recorded in
# DEVICE.md -- what matters for this file is only that Node must never be
# allowed to JIT, and that `--jitless` is what prevents it.
#
# ---------------------------------------------------------------------------
# THE RESEARCH RESULT: which mechanism actually works
# ---------------------------------------------------------------------------
#
# There is NO dedicated environment variable.  This was checked against the
# Node v22.23.4 source rather than assumed:
#
#   * `grep -rn jitless src/ lib/ deps/uv/src` finds exactly ONE definition
#     site: src/node_options.cc:1068, `AddOption("--jitless", ...)`.  It is
#     registered as V8Option{} -- it is a V8 flag re-exported by Node, not a
#     Node env-var-backed setting.
#   * There is no `NODE_JITLESS`.  No such string exists anywhere in the
#     tree.  (The V8 side has `V8_JITLESS_BOOL` in deps/v8/src/flags/
#     flag-definitions.h, but that is a *compile-time* macro, V8_JITLESS --
#     not an environment variable, and not something we set.)
#   * `--jitless` IS in the NODE_OPTIONS allow-list.  Two independent
#     confirmations: the generated list in doc/api/cli.md ("V8 options that
#     are allowed are: ... * `--jitless`") and the flag's own registration,
#     which passes kAllowedInEnvvar.
#
# So the mechanism is: **`NODE_OPTIONS=--jitless`**, optionally combined
# with a literal `--jitless` on the command line.  The env var is the part
# that makes it user-invisible, which is the whole point of this wrapper.
#
# ORDER AND OVERRIDE BEHAVIOUR (from src/node.cc:1010-1024): NODE_OPTIONS is
# parsed first, then real argv.  doc/api/cli.md: "Options from the command
# line take precedence over options passed through NODE_OPTIONS" and "a
# singleton flag passed as a command-line option will override the same flag
# passed into NODE_OPTIONS".
#
# Consequence, and it is worth being explicit: NODE_OPTIONS is the *default*,
# not a lock.  There is no `--no-jitless` in V8, so a user cannot actually
# turn it back on by spelling it differently -- but because the user's argv
# is appended after the env var's, the flag can in principle be re-stated.
# V8 treats `--jitless` as a plain boolean with no negative form, so the
# only way to defeat this wrapper is to build a different binary.  We still
# do not claim it is airtight.
#
# `--jitless` is marked Stability 1 - Experimental in the Node 22 docs and
# is inherited from V8, so it can change upstream.  VERIFY.md pins it down
# on the device instead of trusting this comment.
#
# ---------------------------------------------------------------------------
# WHAT IS VERIFIED AND WHAT IS NOT
# ---------------------------------------------------------------------------
#
# VERIFIED ON THE HOST, TODAY (against the actual v22.23.4 source tree):
#   * `--jitless` is the only spelling; no NODE_JITLESS exists.
#   * `--jitless` is allowed in NODE_OPTIONS.
#   * NODE_OPTIONS is parsed before argv.
#   * `ldid -e` exits 0 only on a signed file (exit 1 before `ldid -S`,
#     0 after) -- the assertion make-deb.sh relies on.
#
# NOT VERIFIED (no armv7 Node binary exists yet):
#   * That `NODE_OPTIONS=--jitless node -e 'console.log(1)'` actually prints
#     1 on this device.  This is the single most important thing to run
#     first once the build lands; it is item 2 of VERIFY.md.
#   * That the process really does not allocate executable memory under
#     --jitless, and that this is what keeps the kernel from killing it.
#     That claim is inherited from the V8 docs, not measured here.
#   * Startup and throughput cost of jitless on this CPU.  Expect it to be
#     severe (the Node docs say "the performance impact may be severe"); no
#     number is quoted here because no measurement exists.
#
# ---------------------------------------------------------------------------
# WHY "$@" IS PRESERVED EXACTLY
# ---------------------------------------------------------------------------
#
# NODE_OPTIONS is set for the *engine* process only (it is exported for the
# exec below and not for anything else), and the argument vector is passed
# through untouched.  Two things deliberately do NOT happen:
#
#   * We do not prepend `--jitless` to "$@".  Doing so would move the flag
#     into argv, where it would appear in process.execArgv and, worse, would
#     be inherited by child processes that re-exec node -- turning a
#     per-process default into something that shows up in `ps`.  NODE_OPTIONS
#     is inherited by children anyway (that is desirable: a child node is
#     still on the same CPU), but it stays out of argv.
#   * We do not `exec` a shell.  `exec "$real" "$@"` replaces this process,
#     so the PID, the exit status, the signal disposition and stdin/stdout
#     all belong to the engine.  A wrapper that forked would break
#     `node -e 'process.kill(process.pid)'`, `$!` in shell scripts, and
#     anything reading /proc-equivalent state.
set -euo pipefail

# Resolve this script's own directory through any symlink chain.  The
# installed name is a plain file, but /usr/local/bin/node is expected to be
# a symlink to it (make-deb.sh does not create that link -- see the README
# note on shadowing -- so a user may), and $0 would then point at /usr/
# local/bin.  `readlink -f` does not exist on iOS; this loop does.
self="$0"
while [ -L "$self" ]; do
    target="$(readlink "$self")"
    case "$target" in
        /*) self="$target" ;;
        *)  self="$(dirname "$self")/$target" ;;
    esac
done
dir="$(cd "$(dirname "$self")" && pwd)"
real="$dir/node.real"

[ -x "$real" ] || {
    echo "jitless-wrap: $real is missing or not executable" >&2
    echo "              (this wrapper is only meaningful where make-deb.sh" >&2
    echo "               installed it, next to the real node binary)" >&2
    exit 127
}

# `-` prefix rather than `:=`: if NODE_OPTIONS is already set we append
# instead of clobbering, so a caller who needs e.g. --max-old-space-size on
# a 1 GB device keeps it.  A user who has already put --jitless in there
# just gets it twice, which V8 tolerates.
export NODE_OPTIONS="--jitless${NODE_OPTIONS:+ $NODE_OPTIONS}"

exec "$real" "$@"
