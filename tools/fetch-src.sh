#!/bin/bash
# tools/fetch-src.sh -- one verified download path for every source tarball.
#
# Every */build.sh fetches its sources through this script, and every entry it
# is called with must exist in ../../sources.lock (pkg/version/url/sha256).
# Downloads land in a single content cache:
#
#   SRC_CACHE (default $HOME/ios-armv7-builder/tmp/src-cache, gitignored)
#       <pkg>/<basename-of-url>
#
# NOT in /tmp on purpose: /tmp on the build hosts is a small tmpfs and the
# big payloads (node is ~110 MB) blow its quota (see AGENTS.md rule 0).
#
# Usage:
#   tools/fetch-src.sh <pkg> <url> <sha256> [dest]
#       Cache hit with matching sha256  -> reused, no network access.
#       Cache miss                      -> downloaded, sha256-verified, cached.
#       sha256 mismatch                 -> error, exit 1 (never silently used).
#       [dest] (optional) also materialises the verified file at <dest>
#       (hardlink when possible) for consumers that need a fixed legacy path.
#       Prints the path of the verified file -- use it directly:
#           tar xzf "$("$root/tools/fetch-src.sh" pkg "$url" "$sha")"
#
#   tools/fetch-src.sh --lock <pkg>
#       Print "<url> <sha256> [<filename>]" for <pkg> straight from
#       sources.lock, so build.sh never hardcodes either:
#           read -r URL SHA <<<"$("$root/tools/fetch-src.sh" --lock tcpdump)"
#       (build.sh may also grep sources.lock inline; both are equivalent.)
#
#   tools/fetch-src.sh --check [pkg...]
#       Verify cached files against sources.lock.  No arguments = every entry.
#       Exit 1 if anything is missing or mismatched.  CI gate.
#
#   tools/fetch-src.sh --list
#       List the cache contents (pkg, size, sha256 prefix).
#
# The special sha256 value "ANY" skips verification with a loud warning; it is
# only for lock entries that are deliberately unpinned (rolling master
# branches -- whois, class-dump, gas-preprocessor).  Pinned versions must
# always carry a real sha256.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
SRC_CACHE="${SRC_CACHE:-$HOME/ios-armv7-builder/tmp/src-cache}"
LOCK="${SOURCES_LOCK:-$root/sources.lock}"

die() { printf 'fetch-src: [x] %s\n' "$*" >&2; exit 1; }
warn() { printf 'fetch-src: [!] %s\n' "$*" >&2; }

sha_of() { sha256sum "$1" | cut -d' ' -f1 | tr 'A-F' 'a-f'; }
norm()   { printf '%s' "$1" | tr 'A-F' 'a-f'; }

[ $# -ge 1 ] || die "usage: fetch-src.sh <pkg> <url> <sha256> [dest] | --lock <pkg> | --check [pkg...] | --list"

# ---------------------------------------------------------------- --lock ----
if [ "$1" = "--lock" ]; then
    [ $# -eq 2 ] || die "usage: fetch-src.sh --lock <pkg>"
    [ -f "$LOCK" ] || die "no lock file at $LOCK"
    row="$(awk -F'\t' -v p="$2" '$1==p && $1!~/^#/ {print $3"\t"$4; exit}' "$LOCK")"
    [ -n "$row" ] || die "package '$2' has no row in $LOCK"
    url="$(printf '%s' "$row" | cut -f1)"
    sha="$(printf '%s' "$row" | cut -f2)"
    fname="$(basename "$url")"
    printf '%s %s %s\n' "$url" "$sha" "$fname"
    exit 0
fi

# --------------------------------------------------------------- --check ----
if [ "$1" = "--check" ]; then
    shift
    [ -f "$LOCK" ] || die "no lock file at $LOCK"
    pkgs="$*"
    if [ -z "$pkgs" ]; then
        pkgs="$(awk -F'\t' '$1!~/^#/ && NF>=4 {print $1}' "$LOCK" | sort -u)"
    fi
    bad=0
    for pkg in $pkgs; do
        row="$(awk -F'\t' -v p="$pkg" '$1==p && $1!~/^#/ {print $3"\t"$4; exit}' "$LOCK")"
        if [ -z "$row" ]; then
            printf 'check: %-16s NOT IN LOCK\n' "$pkg"; bad=1; continue
        fi
        url="$(printf '%s' "$row" | cut -f1)"
        want="$(norm "$(printf '%s' "$row" | cut -f2)")"
        f="$SRC_CACHE/$pkg/$(basename "$url")"
        if [ ! -f "$f" ]; then
            printf 'check: %-16s MISSING  %s\n' "$pkg" "$f"; bad=1; continue
        fi
        got="$(sha_of "$f")"
        if [ "$got" = "$want" ]; then
            printf 'check: %-16s OK       %s\n' "$pkg" "$(du -h "$f" | cut -f1)"
        else
            printf 'check: %-16s MISMATCH want=%s got=%s\n' "$pkg" "$want" "$got"; bad=1
        fi
    done
    [ "$bad" -eq 0 ] || die "cache verification failed"
    echo "check: all entries OK"
    exit 0
fi

# ---------------------------------------------------------------- --list ----
if [ "$1" = "--list" ]; then
    [ -d "$SRC_CACHE" ] || { echo "(cache empty: $SRC_CACHE)"; exit 0; }
    find "$SRC_CACHE" -type f ! -name '*.part' ! -name 'manifest.*' ! -name '*.sh' -printf '%s\t%p\n' \
        | sort -k2 | while IFS=$'\t' read -r sz path; do
            printf '%8s  %-12s %s\n' "$(du -h "$path" | cut -f1)" \
                "$(sha256sum "$path" | cut -c1-12)" "${path#$SRC_CACHE/}"
        done
    exit 0
fi

# ------------------------------------------------------------- fetch mode ---
[ $# -ge 3 ] || die "usage: fetch-src.sh <pkg> <url> <sha256> [dest]"
pkg="$1"; url="$2"; want="$3"; dest="${4:-}"

[ -n "$want" ] || die "empty sha256 for pkg '$pkg' -- add/repair its row in $LOCK (pkg<TAB>version<TAB>url<TAB>sha256)"
if [ "$want" = "ANY" ]; then
    warn "sha256=ANY: downloading $pkg WITHOUT verification (lock entry is unpinned)"
else
    want="$(norm "$want")"
    case "$want" in
        *[!a-f0-9]*|'') die "not a sha256 hex digest: '$3'" ;;
    esac
    [ "${#want}" -eq 64 ] || die "sha256 must be 64 hex chars, got ${#want}: '$3'"
fi

cached="$SRC_CACHE/$pkg/$(basename "$url")"
mkdir -p "$SRC_CACHE/$pkg"

if [ -f "$cached" ]; then
    if [ "$want" != "ANY" ]; then
        got="$(sha_of "$cached")"
        if [ "$got" != "$want" ]; then
            die "cached file is corrupt: $cached
       sha256 now: $got
       expected  : $want
       delete it and re-run to re-download"
        fi
    fi
    echo "fetch-src: cache hit $pkg ($(du -h "$cached" | cut -f1))" >&2
else
    echo "fetch-src: downloading $pkg" >&2
    echo "fetch-src:   $url" >&2
    rm -f "$cached.part"
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 \
        --speed-limit 512 --speed-time 180 --max-time 3600 \
        -o "$cached.part" "$url" \
        || die "download failed: $url (partial file removed; no cache entry created)"
    if [ "$want" != "ANY" ]; then
        got="$(sha_of "$cached.part")"
        if [ "$got" != "$want" ]; then
            rm -f "$cached.part"
            die "sha256 mismatch for $pkg from
       $url
       expected : $want
       got      : $got
       nothing was cached; fix the URL/lock row or re-download"
        fi
    fi
    mv "$cached.part" "$cached"
    echo "fetch-src: cached $cached ($(du -h "$cached" | cut -f1))" >&2
fi

# Optional fixed-path materialisation for legacy consumers (e.g. nginx seeds
# its private pcre2 tree from nmap's tarball at a hardcoded path).
if [ -n "$dest" ]; then
    if [ ! -f "$dest" ] || [ "$(sha_of "$dest")" != "$(sha_of "$cached")" ]; then
        mkdir -p "$(dirname "$dest")"
        ln -f "$cached" "$dest" 2>/dev/null || cp -f "$cached" "$dest"
    fi
    printf '%s\n' "$dest"
else
    printf '%s\n' "$cached"
fi