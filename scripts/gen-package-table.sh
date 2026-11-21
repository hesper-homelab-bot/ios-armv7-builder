#!/bin/bash
# gen-package-table.sh -- generate docs/PACKAGES.md from the APT Packages
# index, so the "what exists" documentation cannot drift from what the repo
# actually ships.  Regenerate on every repo rebuild.
#
# Columns: package | version | build recipe | docs | device acceptance
#   - build recipe: <base>/ directory when present, else '--'
#   - docs: docs/<base>.md when present (a few names need a manual mapping)
#   - device acceptance: tests/<base>.sh + its case count, when present
#
# Usage: scripts/gen-package-table.sh [out-file]   (default docs/PACKAGES.md)
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$here/docs/PACKAGES.md}"
idx="$here/repo/dists/stable/main/binary-iphoneos-arm/Packages"
[ -f "$idx" ] || { echo "repo not built; run scripts/make-repo.sh first" >&2; exit 1; }

python3 - "$here" "$idx" "$out" <<'PY'
import re, sys, os
repo, idx_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

stanzas = []
for stanza in open(idx_path).read().split('\n\n'):
    if not stanza.strip():
        continue
    get = lambda k: (re.search(rf'^{k}: (.*)$', stanza, re.M) or [None, ''])[1]
    stanzas.append((get('Package'), get('Version'), get('Description')))

DOC_MAP = {'python314': 'python', 'whois4': 'whois', 'netstat4': 'netstat',
           'ifconfig4': 'ifconfig', 'traceroute4': 'traceroute',
           'wget4': 'wget', 'tor4': 'tor', 'openssh4': 'openssh',
           'dropbear4': 'dropbear', 'dns4': 'dns'}

def base_of(pkg):
    return DOC_MAP.get(pkg, pkg[:-1] if pkg.endswith('4') else pkg)

rows = []
for pkg, ver, desc in sorted(stanzas):
    base = base_of(pkg)
    recipe = f'`{base}/`' if os.path.isdir(os.path.join(repo, base)) else '--'
    docs_f = f'docs/{base}.md'
    docs_cell = f'[{docs_f}]({docs_f})' if os.path.exists(os.path.join(repo, docs_f)) else '--'
    tests_f = f'tests/{base}.sh'
    if os.path.exists(os.path.join(repo, tests_f)):
        n = len(re.findall(r'expect_', open(os.path.join(repo, tests_f)).read()))
        acc = f'[{tests_f}]({tests_f}), {n} cases'
    else:
        acc = '--'
    d = (desc or '').split('.')[0].strip()[:64]
    rows.append(f'| {pkg} | {ver} | {recipe} | {docs_cell} | {acc} |')

open(out_path, 'w').write('\n'.join([
    '# Package index (generated)',
    '',
    'Generated from the APT `Packages` index by',
    '`scripts/gen-package-table.sh` -- do not edit by hand; it regenerates',
    'on every repo rebuild.',
    '',
    f'{len(stanzas)} debs in `repo/pool`:',
    '',
    '| package | version | build recipe | docs | device acceptance |',
    '|---|---|---|---|---|',
    *rows,
]) + '\n')
print(f'==> {out_path}: {len(stanzas)} packages')
PY