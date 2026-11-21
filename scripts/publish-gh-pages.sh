#!/bin/bash
# Publish repo/ (as produced by scripts/make-repo.sh) to the gh-pages branch.
#
# The tree is pushed under gh-pages's repo/ subdirectory -- the same path the
# main branch used to carry -- so the public URL
#     https://hesper-homelab-bot.github.io/ios-armv7-builder/repo
# never changes, whichever branch GitHub Pages is currently serving.
#
# gh-pages is force-pushed as a single orphan commit every time, so binary
# accumulation cannot grow it: the branch is always exactly one snapshot.
# The main branch never carries the debs after the 2026-11-21 history rewrite
# (out/ and repo/ are gitignored there).
#
# Usage:  scripts/publish-gh-pages.sh        # publishes ./repo to origin
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
url="$(git -C "$here" remote get-url origin)"
[ -d "$here/repo/pool" ] || { echo "repo/ not built; run scripts/make-repo.sh first" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo"
cp -r "$here/repo/." "$tmp/repo/"
cat > "$tmp/index.html" <<'HTML'
<!doctype html><meta charset=utf-8>
<title>ios-armv7-builder APT repo</title>
<p>APT/Cydia source: <code>deb https://hesper-homelab-bot.github.io/ios-armv7-builder/repo stable main</code>
<p>Signing key: <a href="repo/hesper-homelab-bot.asc">hesper-homelab-bot.asc</a>
HTML
cd "$tmp"
git init -q -b gh-pages
git add -A
git -c user.name="hesper-homelab-bot" \
    -c user.email="hesper-homelab-bot@users.noreply.github.com" \
    commit -qm "publish APT repo $(date -u +%FT%TZ)"
git remote add origin "$url"
git push -f -q origin gh-pages
echo "==> pushed gh-pages (single orphan commit, repo/ subtree) to $url"
