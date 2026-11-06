#!/bin/bash
# Package the armv7 curl + OpenSSL builds into .deb files for the APT repo.
#
# Both packages install under /var/mobile so nothing in /usr is touched:
# the device's sshd and everything else keep working if these are removed.
# Uninstalling is just `rm -rf /var/mobile/openssl4`.
#
# Usage:
#   ./curl/make-deb.sh                 # uses ../out/curl-*-armv7
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
CURL_VERSION="${CURL_VERSION:-8.16.0}"
OSSL_VERSION="${OSSL_VERSION:-4.0.3}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"

CURL_BIN="$OUT/curl-$CURL_VERSION-armv7"
OSSL_BIN="$OUT/openssl-$OSSL_VERSION-armv7"
[ -f "$CURL_BIN" ] || { echo "missing $CURL_BIN (run curl/build.sh)" >&2; exit 1; }
[ -f "$OSSL_BIN" ] || { echo "missing $OSSL_BIN (run openssl/build.sh)" >&2; exit 1; }

sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst" || { echo "cp failed: $src -> $dst" >&2; exit 1; }

    # Failures here must be loud.  This function used to end in
    #     ldid -S "$dst" 2>/dev/null || true
    # which swallowed everything, and the binary that reached the package was
    # then *unsigned* -- and an unsigned Mach-O is killed by the device with
    # SIGKILL and no crash report, before main().  That is the whole origin of
    # the "host ldid occasionally produces a binary the device kills with
    # Killed: 9" folklore: not host ldid being unreliable, but this
    # swallowing the failure.  See the signing section in README.
    command -v ldid >/dev/null 2>&1 || {
        echo "ldid is not on PATH -- refusing to package an unsigned binary" >&2
        exit 1
    }
    ldid -S "$dst" || {
        echo "ldid -S failed for $dst" >&2
        exit 1
    }

    # ldid -e exits 0 only when the file actually carries a signature (verified
    # by signing a copy of an unsigned binary and re-checking), so this is a
    # real assertion rather than a formality.
    ldid -e "$dst" >/dev/null 2>&1 || {
        echo "$dst carries no signature after ldid -S" >&2
        exit 1
    }
}


# ---------------------------------------------------------------- openssl ---
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/openssl4" "$w/usr/share/doc/openssl4"
cat > "$w/DEBIAN/control" <<CTRL
Package: openssl4
Name: OpenSSL 4
Version: $OSSL_VERSION-$DEBREV
Section: Security
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://www.openssl.org
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: OpenSSL 4 command line tool (armv7 iOS 10+)
 OpenSSL 4.0.3 built for armv7 iOS 10.x.  Installs an isolated copy under
 /var/mobile/openssl4 so it never shadows the system libraries that sshd
 and the rest of iOS depend on.
 .
 Provides: openssl
 Replaces: openssl
 Conflicts: openssl
CTRL

cat > "$w/usr/share/doc/openssl4/copyright" <<'CR'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: OpenSSL
Source: https://github.com/openssl/openssl

Files: *
Copyright: 1998-2026 The OpenSSL Project Authors
License: Apache-2.0
 Licensed under the Apache License 2.0.
 .
 Cross-compiled for armv7 iOS 10.x.  The sysroot headers used to build it
 are original clean-room stubs or BSD-licensed musl headers; no Apple SDK
 files are redistributed.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: Apache-2.0
CR

sign "$OSSL_BIN" "$w/var/mobile/openssl4/openssl"
chmod 0755 "$w/var/mobile/openssl4/openssl"
deb1="$OUT/openssl4_${OSSL_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb1" >/dev/null
rm -rf "$w"; trap - EXIT

# ------------------------------------------------------------------- curl ---
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools" "$w/usr/share/doc/curl4"
cat > "$w/DEBIAN/control" <<CTRL
Package: curl4
Name: curl 8
Version: $CURL_VERSION-$DEBREV
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://curl.se
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: curl with HTTPS for armv7 iOS 10+ (static OpenSSL 4)
 curl 8.16.0 for armv7 iOS 10.x, statically linked against OpenSSL 4.0.3.
 Installs to /var/mobile/tools/curl, so it does not replace any system
 binary.
 .
 Set SSL_CERT_FILE=/etc/ssl/cert.pem to verify HTTPS certificates, or put
 it in /var/mobile/tools/env.sh.
CTRL

cat > "$w/usr/share/doc/curl4/copyright" <<'CR'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: curl
Source: https://github.com/curl/curl

Files: *
Copyright: 1996-2026 Daniel Stenberg and curl contributors
License: curl
 Permission to use, copy, modify, and distribute this software for any
 purpose with or without fee is hereby granted, provided that the above
 copyright notice and this permission notice appear in all copies.

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: curl
CR

sign "$CURL_BIN" "$w/var/mobile/tools/curl"
chmod 0755 "$w/var/mobile/tools/curl"
deb2="$OUT/curl4_${CURL_VERSION}-${DEBREV}_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb2" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb1"
sha256sum "$deb1"
echo "==> $deb2"
sha256sum "$deb2"
