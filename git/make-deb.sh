#!/bin/bash
# Package the armv7 git build into a .deb for the APT repo.
#
# Follows ../wget/make-deb.sh: installs under /var/mobile/tools, nothing in
# /usr is touched, uninstalling is just removing the directory.  Fully static
# (libz, libcurl, libssl, libcrypto are all .a), so no Depends beyond
# firmware.
#
# Usage:
#   ./git/make-deb.sh                 # uses ../tmp/git-staging from build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
GIT_VERSION="${GIT_VERSION:-2.51.2}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
STAGING="${STAGING:-$root/tmp/git-staging}"

[ -d "$STAGING/var/mobile/tools/bin" ] || { echo "missing $STAGING (run git/build.sh first)" >&2; exit 1; }

# Host ldid occasionally produces a binary the device kills with "Killed: 9"
# and no crash report; signing on the device always works.  The packaging
# scripts therefore sign twice, exactly as curl/make-deb.sh does.  git has
# many binaries (bin/* plus the helpers in libexec/git-core), so sign every
# Mach-O the staging tree contains.
find "$STAGING" -type f -print0 | while IFS= read -r -d '' f; do
    if file "$f" | grep -q Mach-O; then
        ldid -S "$f" 2>/dev/null || true
    fi
done

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/share/doc/git"
cp -a "$STAGING/var" "$w/"
cp -a "$STAGING/etc" "$w/" 2>/dev/null || true

# Default TLS trust store.  libcurl.a does not pick up SSL_CERT_FILE the way
# the installed curl binary does, so git would fail with "unable to get local
# issuer certificate" on the first https clone; ship the CA path explicitly
# (verified on the device: -c http.sslCAInfo=/etc/ssl/cert.pem fixes it).
# NOTE: git's compiled-in sysconfdir is /var/mobile/tools/etc (config.mak),
# NOT the system /etc -- never write into the device's /etc.
mkdir -p "$w/var/mobile/tools/etc"
cat > "$w/var/mobile/tools/etc/gitconfig" <<GCFG
[http]
	sslCAInfo = /etc/ssl/cert.pem
GCFG

cat > "$w/DEBIAN/control" <<CTRL
Package: git
Name: Git 2.51
Version: $GIT_VERSION-$DEBREV
Section: Development
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://git-scm.com/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: Git 2.51.2 for armv7 iOS 10+ (fully static)
 Git $GIT_VERSION for armv7 iOS 10.x.  Everything is statically linked
 (zlib, libcurl, OpenSSL 4.0.3), so there are no runtime library
 dependencies.  Installs under /var/mobile/tools; nothing in /usr is
 touched.
 .
 Add /var/mobile/tools/bin to your PATH (or source
 /var/mobile/tools/env.sh), then set your identity once:
   git config --global user.name "you"
   git config --global user.email "you@example.org"
 .
 Working: init/add/commit/log/diff/status/branch/merge/rebase, clone,
 fetch and push over HTTPS (git-remote-http) and file://, git-shell.
 Not built (no perl on the device): git-send-email, gitweb, cvsserver.
 .
 HTTPS certificate verification needs SSL_CERT_FILE=/etc/ssl/cert.pem
 (see /var/mobile/tools/env.sh).
CTRL

cat > "$w/usr/share/doc/git/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: git
Source: https://github.com/git/git/archive/refs/tags/v$GIT_VERSION.tar.gz

Files: *
Copyright: 2005-2026 Linus Torvalds, Junio C Hamano and the git contributors
License: GPL-2.0
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; version 2 of the License.
 .
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: GPL-2.0

Cross-compiled for armv7 iOS 10.x.  The sysroot headers used to build it are
original clean-room stubs or BSD-licensed musl headers; no Apple SDK files
are redistributed.  Statically linked against zlib 1.3.1, libcurl 8.16.0 and
OpenSSL 4.0.3 built from this same repository.
CR

deb="$OUT/git_${GIT_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device:"
echo "      cp $deb /var/mobile/ && dpkg -i $deb"
