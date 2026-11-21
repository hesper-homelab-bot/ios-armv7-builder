#!/bin/bash
# ca-certificates/build.sh -- fetch and verify the Mozilla CA bundle.
#
# Nothing gets compiled: this package is data plus one shell script.  The
# build step exists so the bundle enters the tree the same verified way as
# every other source (pinned in sources.lock, cached in SRC_CACHE, sha256
# checked on every rebuild) and so the repo never ships an unreviewed PEM.
#
# Usage: ./ca-certificates/build.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/out"
mkdir -p "$out"

# --lock prints "url sha256 [filename]" -- drop the filename column
read -r URL SHA _ <<<"$("$root/tools/fetch-src.sh" --lock ca-bundle)"
bundle="$("$root/tools/fetch-src.sh" ca-bundle "$URL" "$SHA" \
          "$out/ca-certificates-ca-bundle.pem")"

n=$(grep -c "BEGIN CERTIFICATE" "$bundle")
[ "$n" -ge 100 ] || { echo "bundle sanity failed: $n certificates" >&2; exit 1; }
echo "==> bundle ready: $n certificates, $(wc -c < "$bundle") bytes"
