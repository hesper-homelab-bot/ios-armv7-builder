#!/bin/bash
# tests/openssl.sh -- device acceptance for the OpenSSL 4 package.
# README table: version / rand -hex / dgst -sha256 all verified; the sha256
# known-answer here is the standard "abc" vector (FIPS 180-2).
source "$(dirname "$0")/lib.sh"
O=/var/mobile/openssl4/openssl

expect_out "openssl: version 4.0.3"     "$O version" "OpenSSL 4.0.3"
expect_out "openssl: rand 64 hex"       "$O rand -hex 32 | grep -cE '^[0-9a-f]{64}$'" "1"
expect_out "openssl: sha256(abc) KAT"   "printf abc | $O dgst -sha256" \
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

summary openssl
