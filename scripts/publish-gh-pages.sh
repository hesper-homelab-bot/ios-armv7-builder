#!/bin/bash
# Publish repo/ (as produced by scripts/make-repo.sh) to the gh-pages branch.
#
# gh-pages is force-pushed as a single orphan commit every time, so binary
# accumulation cannot grow it: the branch is always exactly one snapshot of
# the current repo.  The main branch never carries the debs after the
# 2026-11-21 history rewrite (out/ and repo/ are gitignored).
#
# Usage:  scripts/publish-gh-pages.sh        # publishes ./repo to origin
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
url="$(git -C "$here" remote get-url origin)"
[ -d "$here/repo/pool" ] || { echo "repo/ not built; run scripts/make-repo.sh first" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -r "$here/repo/." "$tmp/"
cd "$tmp"
git init -q -b gh-pages
git add -A
git -c user.name="hesper-homelab-bot" \
    -c user.email="hesper-homelab-bot@users.noreply.github.com" \
    commit -qm "publish APT repo $(date -u +%FT%TZ)"
git remote add origin "$url"
git push -f -q origin gh-pages
echo "==> pushed gh-pages (single orphan commit) to $url"
