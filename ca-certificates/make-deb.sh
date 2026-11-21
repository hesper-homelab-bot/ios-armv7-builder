#!/bin/bash
# Package the Mozilla CA bundle + update script into a .deb for the APT repo.
#
# Pure data package -- no binaries, no signing step, nothing that executes at
# install time.  It ships:
#   /var/mobile/tools/etc/ca-certificates/ca-bundle.crt   Mozilla trust store
#   /var/mobile/tools/bin/update-ca-certificates          refresher script
#   /var/mobile/tools/etc/ca-certificates/README          runtime entry points
#
# The system /etc/ssl/cert.pem (iOS 10.3 vintage) is never touched; runtimes
# are switched to the managed bundle explicitly (docs/ca-certificates.md).
#
# Usage: ./ca-certificates/make-deb.sh      # after ./ca-certificates/build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
CA_VERSION="${CA_VERSION:-20261121}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"

BUNDLE="$OUT/ca-certificates-ca-bundle.pem"
[ -s "$BUNDLE" ] || { echo "missing bundle; run build.sh first" >&2; exit 1; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" \
         "$w/var/mobile/tools/etc/ca-certificates" \
         "$w/var/mobile/tools/bin" \
         "$w/usr/share/doc/ca-certificates4"

cat > "$w/DEBIAN/control" <<CTRL
Package: ca-certificates4
Name: CA certificates (managed bundle)
Version: $CA_VERSION-$DEBREV
Section: Utilities
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Provides: ca-certificates
Description: Mozilla CA bundle and update script for the armv7 kit
 A single managed trust store: /var/mobile/tools/etc/ca-certificates/
 ca-bundle.crt (Mozilla bundle via curl.se, $(grep -c "BEGIN CERTIFICATE" "$BUNDLE") certificates) plus
 update-ca-certificates, which refreshes it atomically with sanity checks.
 .
 Entry points: SSL_CERT_FILE=.../ca-bundle.crt for curl, wget, python3,
 node and go; git config http.sslCAInfo for git.  The system
 /etc/ssl/cert.pem is left in place -- see docs/ca-certificates.md.
CTRL

cat > "$w/var/mobile/tools/etc/ca-certificates/README" <<'RD'
ca-certificates4
================

ca-bundle.crt is the Mozilla trust store this kit manages; refresh it with:

    /var/mobile/tools/bin/update-ca-certificates

Point a runtime at it:

    export SSL_CERT_FILE=/var/mobile/tools/etc/ca-certificates/ca-bundle.crt   # curl/wget/python3/node/go
    git config --global http.sslCAInfo /var/mobile/tools/etc/ca-certificates/ca-bundle.crt

The device's stock /etc/ssl/cert.pem (iOS 10.3 era, ~120 certs, missing
modern roots like ISRG X2) is left untouched by this package.
RD

install -m 0644 "$BUNDLE" "$w/var/mobile/tools/etc/ca-certificates/ca-bundle.crt"
install -m 0755 "$here/update-ca-certificates" "$w/var/mobile/tools/bin/update-ca-certificates"
install -m 0644 "$w/var/mobile/tools/etc/ca-certificates/README" "$w/usr/share/doc/ca-certificates4/README"

deb="$OUT/ca-certificates4_${CA_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
echo "==> $deb"
dpkg-deb -f "$deb" Package Version Architecture
sha256sum "$deb"
