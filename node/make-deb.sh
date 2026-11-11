#!/bin/bash
# Package the armv7 Node.js build into a .deb for the APT repo.
#
# Mirrors ../lsof/make-deb.sh: host ldid signs, the signature is asserted
# with ldid -e, and the failure is loud rather than swallowed (DEVICE.md §7
# and §10 -- this is the rule that replaced "sign twice").
#
# ---------------------------------------------------------------------------
# INSTALL LAYOUT, AND WHY
# ---------------------------------------------------------------------------
#
# Decision: **/var/mobile/tools/node/** -- engine at /var/mobile/tools/node/
# bin/node.real, the jitless wrapper at /var/mobile/tools/node/bin/node, and
# npm/npx next to them.  Reason, from DEVICE.md §9 and §3 and the existing
# device state (checked 2026-11-08):
#
#   * §9 is explicit: "/var/mobile/tools holds only the installed kit
#     binaries".  Every package this repo publishes that is a *tool*
#     installs there -- lsof, curl, and the db-*/ossh-* helpers are all
#     under /var/mobile/tools today.  Node is a tool.  This is the
#     established convention and Node follows it rather than inventing
#     a second one.
#
#   * It is also the only layout that is *removable*.  `dpkg -r node4`
#     leaves the device exactly as it was: nothing under /usr is touched,
#     no system binary is shadowed or replaced.  The alternatives all
#     violate that:
#       - /usr/local/bin/node is on the device (verified: curl, lsof,
#         openssl, scp, sftp, ssh and friends are symlinked there), but
#         §3's rule is that /usr/local/bin is for *symlinks to* the
#         /var/mobile/tools originals, not for the files themselves.  Put
#         the real binary there and dpkg owns a file in a shared directory
#         that a jailbreak restore will not recreate.
#       - /usr/bin/node would be worse still: §3 warns that non-login
#         shells get PATH=/usr/bin:/bin and would pick up Node silently,
#         and that no dpkg-owned path should ever be written over.
#
#   * A directory rather than three loose files, because Node is not one
#     binary: the wrapper *must* be the file named `node` and the engine
#     must *not* be, so they have to travel together.  A directory makes
#     that relationship obvious and makes npm's node_modules root
#     (/var/mobile/tools/node/lib/node_modules) obvious too.
#
#   * `/var/mobile/tools/node` does NOT collide with anything: verified on
#     device, /var/mobile/tools contains bin/, curl, db-*, lsof, ossh-*
#     and no `node`.
#
# The package deliberately does NOT create /usr/local/bin/node or
# /usr/bin/node.  That is a user decision with real consequences (a
# non-login shell would suddenly find `node` on PATH, and a future build
# would clobber it), and the README documents how to do it with a symlink
# when it is wanted.  dpkg should not decide it.
#
# ---------------------------------------------------------------------------
# JITLESS ENFORCEMENT
# ---------------------------------------------------------------------------
#
# The file installed as `node` is node/jitless-wrap.sh, which exports
# NODE_OPTIONS=--jitless and execs node.real.  The research behind that --
# there is no NODE_JITLESS, --jitless is the only mechanism, and it is
# allowed in NODE_OPTIONS -- is in the header of jitless-wrap.sh and is
# summarised in VERIFY.md.  The important packaging consequence: `node` is
# a shell script, so it is 0755 and is NOT signed, while node.real is the
# Mach-O and IS signed exactly once.
#
# npm/npx are wrappers too, but for a different reason: they are small
# scripts that invoke `node` from PATH.  If they invoked node directly they
# would bypass the jitless wrapper, so they are generated here to exec the
# wrapper by absolute path.
#
# Usage:
#   ./node/make-deb.sh                 # uses ../out/node-22.23.4-armv7
#   NODE_BIN=/path/to/node ./node/make-deb.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
NODE_VERSION="${NODE_VERSION:-22.23.4}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
PKGDIR="/var/mobile/tools/node"

# Same signing contract as every other make-deb.sh here.  DEVICE.md §10:
# sign once on the host, assert with ldid -e, and treat any rc=137 on the
# device as "signature missing/corrupt/not-yet-transferred" -- verify the
# transfer with md5 on both sides before blaming the signer.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst" || { echo "cp failed: $src -> $dst" >&2; exit 1; }
    chmod 0755 "$dst"
    command -v ldid >/dev/null 2>&1 || {
        echo "ldid is not on PATH -- refusing to package an unsigned binary" >&2
        exit 1
    }
    ldid -S "$dst" || { echo "ldid -S failed for $dst" >&2; exit 1; }
    # ldid -e exits 0 only on a signed file.  Verified on this host against
    # out/lsof-4.99.7-armv7: exit 1 before `ldid -S`, exit 0 after.
    ldid -e "$dst" >/dev/null 2>&1 || {
        echo "$dst carries no signature after ldid -S" >&2
        exit 1
    }
}

bin="${NODE_BIN:-$OUT/node-$NODE_VERSION-armv7}"
[ -f "$bin" ] || {
    echo "missing $bin -- rerun node/build.sh (or set NODE_BIN)" >&2
    exit 1
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w$PKGDIR/bin" "$w$PKGDIR/lib/node_modules" \
         "$w/usr/share/doc/node4"

# ------------------------------------------------------------------ control --
cat > "$w/DEBIAN/control" <<CTRL
Package: node4
Name: Node.js 22
Version: $NODE_VERSION-$DEBREV
Section: Development
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://nodejs.org
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: Node.js $NODE_VERSION for armv7 iOS 10+ (jitless)
 Node.js $NODE_VERSION, cross-compiled for armv7 iOS 10.x with an embedded
 V8, libuv, OpenSSL, c-ares, zlib and llhttp, all statically linked.
 .
 Installs to $PKGDIR.  Nothing under /usr is touched and no system
 binary is replaced; removing the package leaves the device as it was.
 .
 IMPORTANT: this device cannot execute JIT-generated code -- the kernel
 kills the process.  The \`node\` installed here is therefore a wrapper
 that sets NODE_OPTIONS=--jitless before exec'ing the engine, so jitless
 is the default and the user does not have to remember it.  The engine
 itself is $PKGDIR/bin/node.real.
 .
 Because JIT is off, long-running compute is dramatically slower than on
 a desktop.  Short scripts, file manipulation and npm are the intended
 uses.  There is no Intl (built --with-intl=none) and no startup snapshot
 (built --without-node-snapshot), so \`node -e\` has a noticeable fixed
 startup cost.
CTRL

# ----------------------------------------------------------------- postinst --
# Symlinks are created here rather than shipped as files in the archive
# because dpkg-deb --root-owner-group would freeze whatever they pointed at
# at build time, and because §3's rule is that links must be reversible.
#
# Note what is NOT linked: /usr/local/bin/node and /usr/bin/node.  See the
# header -- that is a user decision, not a packaging one.
cat > "$w/DEBIAN/postinst" <<'POST'
#!/bin/sh
# Create the convenience symlinks and report the jitless state.
set -e

PKGDIR=/var/mobile/tools/node
BINDIR="$PKGDIR/bin"

# npm/npx are generated wrappers that call the jitless `node` by absolute
# path, rather than upstream's scripts that call `node` from PATH -- a PATH
# lookup could reach a different node, or the engine directly.
for t in npm npx; do
    if [ -f "$BINDIR/$t.real" ]; then
        cat > "$BINDIR/$t" <<EOF
#!/bin/sh
# Generated by the node4 package: force jitless through the wrapper.
exec "$BINDIR/node" "$BINDIR/$t.real" "\$@"
EOF
        chmod 0755 "$BINDIR/$t"
    fi
done

# /var/mobile/tools/bin is the kit's shared bin directory (verified present
# on device, alongside curl/lsof).  Link there, do not copy.
if [ -d /var/mobile/tools/bin ]; then
    for t in node npm npx; do
        [ -x "$BINDIR/$t" ] || continue
        ln -sf "$BINDIR/$t" "/var/mobile/tools/bin/$t"
    done
fi

# The device's own ldid is at /usr/bin/ldid.  We do NOT re-sign: DEVICE.md
# §10 refuted "sign twice" -- the incident was one unreproducible kill whose
# root cause is unresolved, and 16/16 single-signed runs passed.  This is
# only a check that the transfer did not corrupt the signature.
if command -v ldid >/dev/null 2>&1; then
    if ! ldid -e "$BINDIR/node.real" >/dev/null 2>&1; then
        echo "node4: WARNING: $BINDIR/node.real has no readable signature" >&2
        echo "       the device will kill it with rc=137 before main()." >&2
        echo "       Verify the transfer (md5 both sides) before anything else." >&2
    fi
fi

echo "node4: installed $BINDIR/node (jitless wrapper)"
echo "node4: add to PATH with"
echo "         export PATH=$BINDIR:\$PATH"
echo "       or /usr/local/bin is already on the default PATH;"
echo "         ln -s $BINDIR/node /usr/local/bin/node   # your call, see README"
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"

cat > "$w/DEBIAN/prerm" <<'PRE'
#!/bin/sh
set -e
for t in node npm npx; do
    if [ -L "/var/mobile/tools/bin/$t" ]; then
        rm -f "/var/mobile/tools/bin/$t"
    fi
done
exit 0
PRE
chmod 0755 "$w/DEBIAN/prerm"

# ------------------------------------------------------------- copyright ---
cat > "$w/usr/share/doc/node4/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Node.js
Source: https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION.tar.gz

Files: *
Copyright: Node.js contributors, and the Joyent, Inc. and other Node
 contributors
License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a
 copy of this software and associated documentation files (the
 "Software"), to deal in the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish,
 distribute, sublicense, and/or sell copies of the Software, and to
 permit persons to whom the Software is furnished to do so, subject to
 the following conditions:
 .
 The above copyright notice and this permission notice shall be included
 in all copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.

Files: deps/openssl/*
Copyright: The OpenSSL Project
License: Apache-2.0

Files: deps/v8/*
Copyright: The V8 project authors
License: BSD-3-clause

Files: deps/npm/*
Copyright: npm, Inc.
License: Artistic-2.0

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: MIT

Cross-compiled for armv7 iOS 10.x.  The device cannot execute JIT-generated
code, so the installed `node` is a wrapper that sets NODE_OPTIONS=--jitless
before exec'ing node.real.
CR

# ------------------------------------------------------------------ stage ---
# node.real is the Mach-O: signed, and named so it cannot be confused with
# the wrapper.  `node` is the shell wrapper from jitless-wrap.sh -- never
# signed, because ldid on a shell script would rewrite it as a Mach-O.
sign "$bin" "$w$PKGDIR/bin/node.real"

cp "$here/jitless-wrap.sh" "$w$PKGDIR/bin/node"
chmod 0755 "$w$PKGDIR/bin/node"

# Sanity: the wrapper must reference node.real, or the package installs a
# `node` that either does nothing or runs the engine un-jitless.
grep -q 'node\.real' "$w$PKGDIR/bin/node" || {
    echo "jitless-wrap.sh does not reference node.real -- refusing to package" >&2
    exit 1
}

# --------------------------------------------------------------- checksums --
# File list and per-file sha256, so the device-side verification in
# VERIFY.md has something to compare against.  dpkg already ships md5sums;
# this is the stronger one and it is the one quoted in the install output.
( cd "$w" && find . -type f ! -path './DEBIAN/*' -printf '%P\n' | sort ) \
    > "$w/DEBIAN/node4.list"
( cd "$w" && find . -type f ! -path './DEBIAN/*' -print0 \
    | sort -z | xargs -0 sha256sum | sed 's| \./| |' ) \
    > "$w/DEBIAN/node4.sha256"

deb="$OUT/node4_${NODE_VERSION}-${DEBREV}_iphoneos-arm.deb"
mkdir -p "$OUT"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null

# Keep the manifest with the .deb -- scripts/make-repo.sh scans out/, and
# the manifest is the artifact VERIFY.md diffs against on the device.
cp "$w/DEBIAN/node4.sha256" "$OUT/node4_${NODE_VERSION}-${DEBREV}.sha256"
cp "$w/DEBIAN/node4.list"   "$OUT/node4_${NODE_VERSION}-${DEBREV}.list"

rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    contents:"
sed 's/^/      /' "$OUT/node4_${NODE_VERSION}-${DEBREV}.list"
echo
echo "    per-file sha256: $OUT/node4_${NODE_VERSION}-${DEBREV}.sha256"
echo
echo "    install on device:"
echo "      dpkg -i $(basename "$deb")"
echo "      export PATH=/var/mobile/tools/node/bin:\$PATH"
echo
echo "    then run node/VERIFY.md item 1 before anything else."
