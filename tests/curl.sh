#!/bin/bash
# tests/curl.sh -- device acceptance for the curl package.
# README table: https to github.com / curl.se / cloudflare / apple.com /
# baidu.com all 200.  apple.com is the one live probe kept here (the device
# reaches it; see docs/tailscale.md for why device curl is a poor instrument
# for the tailnet itself).
#
# The CA trust anchor comes from SSL_CERT_FILE=/etc/ssl/cert.pem -- exactly
# what the package's /var/mobile/tools/env.sh exports; a bare https call
# fails with rc=60 (no default issuer store compiled in).  The test mirrors
# the documented usage rather than inventing an env.
source "$(dirname "$0")/lib.sh"
C=/var/mobile/tools/curl

expect_out "curl: version 8.16.0"       "$C --version | head -1" "curl 8.16.0"
expect_out "curl: libcurl runtime"      "$C --version"           "libcurl/8.16.0"
expect_out "curl: https 200 (apple)"    "SSL_CERT_FILE=/etc/ssl/cert.pem $C -s -o /dev/null -w '%{http_code}' --max-time 30 https://www.apple.com/" "200"

summary curl
