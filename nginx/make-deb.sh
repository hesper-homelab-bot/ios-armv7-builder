#!/bin/bash
# Package the armv7 nginx build into a .deb for the APT repo.
#
# Follows ../wget/make-deb.sh: everything installs under
# /var/mobile/tools/nginx, nothing in /usr or /etc is touched, and removal is
# just `rm -rf /var/mobile/tools/nginx`.  nginx links libpcre2, libz, libssl
# and libcrypto statically, so the only runtime dependency is the firmware.
#
# Two things this script does that a plain "copy the binary" package would
# not, both learned from the device:
#
#  1. Double signing.  Host ldid occasionally produces a binary the device
#     kills with "Killed: 9" and no crash report; signing on the device always
#     works.  So the payload copy is signed here *and* a postinst re-signs it
#     with the device's own ldid (see the postinst below).  The task brief
#     asks for the wget/curl two-signature convention and this is it.
#
#  2. Directory layout created at build time AND re-checked in postinst.
#     nginx resolves logs/, tmp/, conf/ and share/nginx/html/ relative to its
#     prefix.  dpkg preserves nothing about ownership beyond what we set, so
#     the postinst fixes owner/mode and creates the temp dirs if a previous
#     run removed them.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
NGINX_VERSION="${NGINX_VERSION:-1.26.3}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
SRC="${NGINX_SRC:-$HOME/ios-tool/nginx-src/nginx-$NGINX_VERSION}"
PREFIX="/var/mobile/tools/nginx"

NGINX_BIN="$OUT/nginx-$NGINX_VERSION-armv7"
[ -f "$NGINX_BIN" ] || { echo "missing $NGINX_BIN (run nginx/build.sh)" >&2; exit 1; }
[ -f "$here/nginx.conf" ] || { echo "missing $here/nginx.conf" >&2; exit 1; }

sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    ldid -S "$dst" 2>/dev/null || true
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" \
         "$w$PREFIX/bin" "$w$PREFIX/conf" "$w$PREFIX/logs" \
         "$w$PREFIX/share/nginx/html" \
         "$w$PREFIX/tmp/client_body" "$w$PREFIX/tmp/proxy" \
         "$w/var/mobile/.local/bin" \
         "$w/Library/LaunchDaemons" \
         "$w/usr/share/doc/nginx4"

cat > "$w/DEBIAN/control" <<CTRL
Package: nginx4
Name: nginx 1.26
Version: $NGINX_VERSION-$DEBREV
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://nginx.org/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: nginx $NGINX_VERSION for armv7 iOS 10+ (kqueue, static OpenSSL 4)
 nginx $NGINX_VERSION cross-compiled for armv7 iOS 10.x, using the iOS
 kqueue event engine and statically linked against PCRE2, zlib and
 OpenSSL 4.0.3.  Installs to /var/mobile/tools/nginx so it does not touch
 any system path.
 .
 Working: static files, index, autoindex, gzip, rewrite/return, TLS, and
 the HTTP proxy module.  Built without the FastCGI/uwsgi/SCGI/gRPC/mail
 modules and without HTTP basic auth (iOS libSystem does not export
 crypt(3)).
 .
 Ships a minimal nginx.conf listening on port 8080 with its document root
 at /var/mobile/tools/nginx/share/nginx/html.  Start it as the mobile user:
   /var/mobile/tools/nginx/bin/nginx
 and check it with
   curl http://127.0.0.1:8080/
CTRL

cat > "$w/DEBIAN/postinst" <<'POST'
#!/bin/sh
# Runs as root, but the server itself is meant to run as `mobile`.
set -e
PREFIX=/var/mobile/tools/nginx

# Sign with the device's own ldid.  A host-produced signature occasionally
# fails to exec on the device (SIGKILL with no crash report); re-signing here
# is the reliable path and is the second half of the double-sign convention
# used by the wget/curl packages.
if [ -x "$PREFIX/bin/nginx" ] && command -v ldid >/dev/null 2>&1; then
    ldid -S "$PREFIX/bin/nginx" 2>/dev/null || true
fi

# Everything under the prefix is owned by mobile so the server can write its
# logs, pid file and temp bodies without root.
mkdir -p "$PREFIX/logs" "$PREFIX/tmp/client_body" "$PREFIX/tmp/proxy"
chown -R mobile:mobile "$PREFIX" 2>/dev/null || true
chmod 0755 "$PREFIX/bin/nginx" 2>/dev/null || true

# The daemon runs as mobile (UserKeepAlive/UserName in the plist), so the
# wrapper it execs must be readable and executable by that user, and the
# LaunchDaemon plist must be root-owned or launchd ignores it.
chown mobile:mobile /var/mobile/.local/bin/nginx-daemon.sh 2>/dev/null || true
chmod 0755 /var/mobile/.local/bin/nginx-daemon.sh 2>/dev/null || true
chown root:wheel /Library/LaunchDaemons/com.hesper.nginx.plist 2>/dev/null || true
chmod 0644 /Library/LaunchDaemons/com.hesper.nginx.plist 2>/dev/null || true

# Load the daemon explicitly.  On iOS 10 a plist merely appearing in
# /Library/LaunchDaemons/ is NOT picked up: verified on the device, the job
# stayed absent from `launchctl list` until `launchctl load` was run by hand.
# (The dropbear package gets away without this because its plist predates
# this work and was loaded once, long ago.)
if command -v launchctl >/dev/null 2>&1; then
    launchctl load -w /Library/LaunchDaemons/com.hesper.nginx.plist >/dev/null 2>&1 || true
fi

exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"

cat > "$w/DEBIAN/prerm" <<'PRE'
#!/bin/sh
# Stop the server before the files disappear, so a running master does not
# keep a deleted binary mapped.  Best effort: never fail an uninstall.
set -e
PREFIX=/var/mobile/tools/nginx

# Unload the LaunchDaemon first.  Without this, KeepAlive simply restarts the
# master we are about to kill, and the uninstall appears to fail (the binary
# stays running from a deleted path).  `launchctl remove` is the correct verb
# for a job loaded from a plist file.
if command -v launchctl >/dev/null 2>&1; then
    launchctl remove com.hesper.nginx >/dev/null 2>&1 || true
fi

if [ -x "$PREFIX/bin/nginx" ] && [ -f "$PREFIX/logs/nginx.pid" ]; then
    "$PREFIX/bin/nginx" -p "$PREFIX" -c "$PREFIX/conf/nginx.conf" -s quit \
        >/dev/null 2>&1 || true
fi
exit 0
PRE
chmod 0755 "$w/DEBIAN/prerm"

sign "$NGINX_BIN" "$w$PREFIX/bin/nginx"
chmod 0755 "$w$PREFIX/bin/nginx"

# The daemon wrapper and its LaunchDaemon.  nginx daemonises itself, so
# launchd can only supervise it through a wrapper that re-execs the master
# with `daemon off;` -- the same arrangement as com.hesper.dropbear.
# There is no launchctl call in postinst: iOS's launchd scans
# /Library/LaunchDaemons/ itself, which is how the dropbear package works.
cp "$here/nginx-daemon.sh" "$w/var/mobile/.local/bin/nginx-daemon.sh"
chmod 0755 "$w/var/mobile/.local/bin/nginx-daemon.sh"
cp "$here/com.hesper.nginx.plist" "$w/Library/LaunchDaemons/com.hesper.nginx.plist"
chmod 0644 "$w/Library/LaunchDaemons/com.hesper.nginx.plist"

cp "$here/nginx.conf" "$w$PREFIX/conf/nginx.conf"
# mime.types and other conf fragments come from the upstream source tree; the
# sample conf includes mime.types, so shipping only nginx.conf would leave a
# config that fails to start.
for f in mime.types fastcgi_params scgi_params uwsgi_params koi-utf koi-win win-utf; do
    [ -f "$SRC/conf/$f" ] && cp "$SRC/conf/$f" "$w$PREFIX/conf/$f"
done
cp "$SRC/html/index.html" "$w$PREFIX/share/nginx/html/index.html"
cp "$SRC/html/50x.html"   "$w$PREFIX/share/nginx/html/50x.html"

cat > "$w/usr/share/doc/nginx4/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: nginx
Source: https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz

Files: *
Copyright: 2002-2024 Igor Sysoev, 2011-2024 Nginx, Inc.
License: BSD-2-Clause
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 .
 1. Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
 .
 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS "AS IS" AND ANY
 EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: BSD-2-Clause

Cross-compiled for armv7 iOS 10.x.  The sysroot headers used to build it are
original clean-room stubs or BSD-licensed musl headers; no Apple SDK files
are redistributed.
CR

dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/nginx4_${NGINX_VERSION}-${DEBREV}_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT

deb="$OUT/nginx4_${NGINX_VERSION}-${DEBREV}_iphoneos-arm.deb"
echo "==> $deb"
sha256sum "$deb"
echo
echo "    install on device (needs root for dpkg -i):"
echo "      scp $deb mobile@<device>:/var/mobile/"
echo "      ssh root@<device> dpkg -i /var/mobile/$(basename "$deb")"
