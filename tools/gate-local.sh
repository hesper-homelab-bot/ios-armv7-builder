#!/bin/bash
# Local equivalent of .github/workflows/gate.yml -- run it before pushing so
# the CI gate never sees a surprise.  Exits non-zero on any failure.
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
rc=0

echo "== bash -n (syntax), maintained scripts =="
for f in $(git ls-files '*.sh' | grep -v '/src/'); do
    bash -n "$f" || { echo "SYNTAX FAIL: $f"; rc=1; }
done
echo "   $(git ls-files '*.sh' | grep -vc '/src/') scripts checked"

if command -v shellcheck >/dev/null; then
    echo "== shellcheck (error level), maintained scripts =="
    if ! shellcheck -S error $(git ls-files '*.sh' | grep -v '/src/'); then
        rc=1
    fi
else
    echo "   shellcheck not installed, skipped"
fi

if [ -f sources.lock ]; then
    echo "== sources.lock =="
    awk -F'\t' 'NR>1 && $0 !~ /^#/ {
        if (NF == 0) next   # blank separator lines are legal
        if ($4 !~ /^[0-9a-f]{64}$/) { print "bad sha256 on line " NR ": " $0; fail=1 }
        if ($3 !~ /^https:\/\//)    { print "non-https URL on line " NR; fail=1 }
        n++
    } END { print "   " n+0 " pinned sources"; exit (fail||0) }' sources.lock || rc=1
else
    echo "== sources.lock: not present yet (see docs/sources-lock.md) =="
fi

[ "$rc" = 0 ] && echo "GATE OK" || echo "GATE FAILED"
exit "$rc"
