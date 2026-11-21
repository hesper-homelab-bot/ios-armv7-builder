#!/bin/bash
# Regenerate the APT/Cydia repository tree (dists + pool) from out/*.deb.
#
# Modernized 2026-11-21 (repo infra):
#   * dpkg-scanpackages  -> apt-ftparchive (exact control metadata, no warnings)
#   * plain Release      -> signed InRelease + Release.gpg (no more
#                           "insecure repository" in Sileo/apt)
#   * repo public key    -> repo/hesper-homelab-bot.asc, imported on the
#                           device once:
#                               wget -qO- <url>/hesper-homelab-bot.asc | apt-key add -
#                           (or Sileo -> Sources -> the prompt when adding)
#   * CydiaIcon.png      -> copied from assets/ so the source is tracked
#   * metadata gate      -> every deb must carry Section/Depiction/Description;
#                           a deb that fails the check aborts the rebuild
#
# Signing key: REPO_GPG_KEY (default = the repo key generated 2026-11-21).
# Pass --no-sign to skip signing (CI gate runs without the private key).
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

KEY="${REPO_GPG_KEY:-2A324C4577AB01949BEA46BC8A6DFC60F7F9E596}"
NO_SIGN=0
[ "${1:-}" = "--no-sign" ] && NO_SIGN=1

# ---------------------------------------------------------------- pool ----
rm -rf repo
mkdir -p repo/dists/stable/main/binary-iphoneos-arm

# metadata gate: Section and Description must be present in the deb control.
# Depiction is *normalized at the Packages index level* below: Sileo reads it
# from the index, so a missing/wrong Depiction inside the deb is a warning
# here (and gets fixed in the index) instead of a hard failure.
REPO_URL="https://github.com/hesper-homelab-bot/ios-armv7-builder"
fail=0
# Only the newest revision of each package reaches the pool: out/ keeps
# superseded revisions around, and shipping both in the pool makes the
# package table (and Sileo) show history nobody asked for.
declare -A BEST_VER BEST_FILE
for f in out/*_iphoneos-arm.deb; do
    [ -e "$f" ] || continue
    pkg="$(dpkg-deb -f "$f" Package)"
    v="$(dpkg-deb -f "$f" Version)"
    for field in Section Description; do
        val="$(dpkg-deb -f "$f" "$field" 2>/dev/null || true)"
        if [ -z "${val// /}" ]; then
            echo "METADATA-GATE FAIL: $pkg: missing $field" >&2; fail=1
        fi
    done
    dep="$(dpkg-deb -f "$f" Depiction 2>/dev/null || true)"
    if [ "$dep" != "$REPO_URL" ]; then
        echo "METADATA-GATE note: $pkg: deb Depiction '${dep:-<none>}' (normalized to $REPO_URL in the index)" >&2
    fi
    if [ -z "${BEST_VER[$pkg]:-}" ] || dpkg --compare-versions "$v" gt "${BEST_VER[$pkg]}"; then
        BEST_VER[$pkg]="$v"; BEST_FILE[$pkg]="$f"
    fi
done
[ "$fail" = 0 ] || { echo "==> metadata gate failed, repo not rebuilt" >&2; exit 1; }
for pkg in "${!BEST_FILE[@]}"; do
    f="${BEST_FILE[$pkg]}"
    mkdir -p "repo/pool/main/${pkg:0:1}/$pkg"
    cp "$f" "repo/pool/main/${pkg:0:1}/$pkg/"
done

# ------------------------------------------------------------ indexes ----
(cd repo && apt-ftparchive --arch iphoneos-arm packages pool \
    > dists/stable/main/binary-iphoneos-arm/Packages)

# Normalize Depiction across the Packages index: replace wrong values and add
# the field to stanzas that lack it.  Stanzas are separated by blank lines.
python3 - "$REPO_URL" <<'PY'
import re, sys
url = sys.argv[1]
path = 'repo/dists/stable/main/binary-iphoneos-arm/Packages'
text = open(path).read()
out, fixed = [], 0
for stanza in re.split(r'\n\n', text.rstrip('\n')):
    if not stanza.strip():
        continue
    if re.search(r'^Depiction:', stanza, re.M):
        new = re.sub(r'^Depiction:.*$', f'Depiction: {url}', stanza, flags=re.M)
    else:
        new = stanza + f'\nDepiction: {url}'
    if new != stanza:
        fixed += 1
    out.append(new)
open(path, 'w').write('\n\n'.join(out) + '\n')
print(f'==> Depiction normalized in {fixed} stanzas')
PY
gzip -9  -c repo/dists/stable/main/binary-iphoneos-arm/Packages \
    > repo/dists/stable/main/binary-iphoneos-arm/Packages.gz
bzip2 -9 -c repo/dists/stable/main/binary-iphoneos-arm/Packages \
    > repo/dists/stable/main/binary-iphoneos-arm/Packages.bz2

# ------------------------------------------------------------- Release ----
(cd repo && apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="hesper-homelab-bot" \
    -o APT::FTPArchive::Release::Label="hesper-homelab-bot iOS Tools" \
    -o APT::FTPArchive::Release::Suite="stable" \
    -o APT::FTPArchive::Release::Version="1.0" \
    -o APT::FTPArchive::Release::Codename="stable" \
    -o APT::FTPArchive::Release::Architectures="iphoneos-arm" \
    -o APT::FTPArchive::Release::Components="main" \
    -o APT::FTPArchive::Release::Description="Cross-compiled tools for armv7 iOS 10.x - built on Linux, no Xcode" \
    release dists/stable) > repo/dists/stable/Release

# -------------------------------------------------------------- signing ----
if [ "$NO_SIGN" = 0 ]; then
    export GPG_TTY="${GPG_TTY:-}"
    gpg --batch --yes --pinentry-mode loopback --local-user "$KEY" \
        --passphrase '' --clearsign \
        -o repo/dists/stable/InRelease repo/dists/stable/Release
    gpg --batch --yes --pinentry-mode loopback --local-user "$KEY" \
        --passphrase '' --armor --detach-sign \
        -o repo/dists/stable/Release.gpg repo/dists/stable/Release
    gpg --armor --export "$KEY" > repo/hesper-homelab-bot.asc
    echo "==> signed with $KEY; public key at repo/hesper-homelab-bot.asc"
else
    echo "==> --no-sign: Release left unsigned (CI gate mode)"
fi

cp assets/CydiaIcon.png repo/CydiaIcon.png

echo "==> repo/ ready:"
find repo -type f | sort
