#!/bin/bash
# tests/uuidgen.sh -- device acceptance for the uuidgen package (e2fsprogs-
# derived).  /var/mobile/tools/uuidgen is the package directory; the
# executable is bin/uuidgen (a symlink into it).  The binary prints
# UPPERCASE hex, so the shape regex accepts both cases.
source "$(dirname "$0")/lib.sh"
U=/var/mobile/tools/bin/uuidgen

expect_out  "uuidgen: canonical v4 shape" \
    "$U | grep -cE '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'" "1"
expect_rc0  "uuidgen: two runs differ"    "[ \"\$($U)\" != \"\$($U)\" ]"

summary uuidgen
