#!/bin/bash
# Regenerate the APT/Cydia repository tree (dists + pool) from out/*.deb.
#
# The resulting repo/ is a plain APT repository: host it on any HTTP server
# (GitHub Pages works) and add it on the device as
#     deb <url> stable main
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

rm -rf repo
mkdir -p repo/dists/stable/main/binary-iphoneos-arm
find out -name '*_iphoneos-arm.deb' -exec bash -c '
    f="{}"; v=$(dpkg-deb -f "$f" Package)
    mkdir -p "repo/pool/main/${v:0:1}/$v"
    cp "$f" "repo/pool/main/${v:0:1}/$v/"
' \;

(cd repo && dpkg-scanpackages --arch iphoneos-arm pool /dev/null \
    > dists/stable/main/binary-iphoneos-arm/Packages 2>/dev/null)
gzip -9  -c repo/dists/stable/main/binary-iphoneos-arm/Packages \
    > repo/dists/stable/main/binary-iphoneos-arm/Packages.gz
bzip2 -9 -c repo/dists/stable/main/binary-iphoneos-arm/Packages \
    > repo/dists/stable/main/binary-iphoneos-arm/Packages.bz2

python3 - <<'PY'
import os, hashlib, time, email.utils
base='repo'
dist='dists/stable'
idx='main/binary-iphoneos-arm'
files=[]
for fn in ('Packages','Packages.gz','Packages.bz2'):
    p=os.path.join(base,dist,idx,fn)
    if os.path.exists(p):
        files.append((f'{idx}/{fn}', open(p,'rb').read()))
rel='''Origin: hesper-homelab-bot
Label: hesper-homelab-bot iOS Tools
Suite: stable
Version: 1.0
Codename: stable
Architectures: iphoneos-arm
Components: main
Description: Cross-compiled tools for armv7 iOS 10.x - built on Linux, no Xcode
Date: %s

''' % email.utils.formatdate(time.time(), localtime=False)
for name, alg in (('MD5Sum', hashlib.md5), ('SHA1', hashlib.sha1), ('SHA256', hashlib.sha256)):
    rel += f'{name}:\n'
    for relpath, data in files:
        rel += f' {alg(data).hexdigest()} {len(data):8d} {relpath}\n'
open(os.path.join(base,dist,'Release'),'w').write(rel)
PY
echo "==> repo/ ready:"
find repo -type f | sort
