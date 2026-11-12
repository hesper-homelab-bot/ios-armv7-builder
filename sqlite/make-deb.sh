#!/bin/bash
# Package the armv7 SQLite build into a .deb for the APT repo.
#
# Follows ../wget/make-deb.sh and ../git/make-deb.sh: installs under
# /var/mobile/tools so nothing in /usr (and nothing in /etc) is touched, and
# uninstalling is just removing the directory.  Fully static -- no Depends
# beyond firmware.
#
# Why /var/mobile/tools/bin and not /usr/bin: iOS already ships a sqlite3
# library (libsqlite3.dylib) that other system components link against.
# Dropping a different sqlite3 binary into /usr/bin would shadow the system
# one for anything that resolves through PATH, and replacing the dylib would
# break the OS.  A private prefix keeps both the shell and the archive
# completely isolated.
#
# Usage:
#   ./sqlite/make-deb.sh              # uses ../tmp/sqlite-staging from build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
SQLITE_VER_DOTTED="${SQLITE_VER_DOTTED:-3.54.1}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
STAGING="${STAGING:-$root/tmp/sqlite-staging}"

[ -x "$STAGING/var/mobile/tools/bin/sqlite3" ] || { echo "missing $STAGING (run sqlite/build.sh first)" >&2; exit 1; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/usr/share/doc/sqlite3"
cp -a "$STAGING/var" "$w/"

# Host ldid occasionally produces a binary the device kills with "Killed: 9"
# and no crash report; signing on the device always works.  The packaging
# scripts therefore sign twice, exactly as curl/make-deb.sh does -- here once
# on the host, and the device-side instructions below sign again.
ldid -S "$w/var/mobile/tools/bin/sqlite3" 2>/dev/null || true

cat > "$w/DEBIAN/control" <<CTRL
Package: sqlite3
Name: SQLite 3.54
Version: $SQLITE_VER_DOTTED-$DEBREV
Section: Development
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://sqlite.org/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: SQLite 3.54.1 command-line shell for armv7 iOS 10+
 SQLite $SQLITE_VER_DOTTED for armv7 iOS 10.x, built from the upstream
 amalgamation (sqlite3.c + shell.c) and fully static -- there are no
 runtime library dependencies at all, not even zlib.
 .
 Installs the shell as /var/mobile/tools/bin/sqlite3 plus the static
 library (libsqlite3.a) and headers (sqlite3.h, sqlite3ext.h) under
 /var/mobile/tools.  Nothing in /usr is touched, so the system's own
 libsqlite3.dylib that iOS components link against is left alone.
 .
 Built with FTS5, R-tree, JSON, math functions, dbstat and column
 metadata enabled.  Extension loading (dlopen) is compiled out: iOS will
 not load unsigned code anyway.
 .
 Add /var/mobile/tools/bin to your PATH (or source
 /var/mobile/tools/env.sh).
CTRL

cat > "$w/usr/share/doc/sqlite3/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: sqlite
Source: https://sqlite.org/2026/sqlite-autoconf-3540100.tar.gz

Files: *
Copyright: none -- SQLite is in the public domain
License: public-domain
 The author disclaims copyright to this source code.  In place of a legal
 notice, here is a blessing:
 .
    May you do good and not evil.
    May you find forgiveness for yourself and forgive others.
    May you share freely, never taking more than you give.
 .
 SQLite is in the public domain.  All the code and documentation in the
 SQLite source tree has been dedicated to the public domain by the
 authors.  There are no licensing restrictions of any kind on any part of
 SQLite.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: public-domain

Cross-compiled for armv7 iOS 10.x.  The sysroot headers used to build it are
original clean-room stubs or BSD-licensed musl headers; no Apple SDK files
are redistributed.
CR

deb="$OUT/sqlite3_${SQLITE_VER_DOTTED}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device:"
echo "      cp $deb /var/mobile/ && dpkg -i $deb"
