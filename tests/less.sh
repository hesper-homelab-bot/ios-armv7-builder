#!/bin/bash
# tests/less.sh -- device acceptance for the less package.
# The binary lives in /var/mobile/tools/bin (the tools/less entry is the
# package's runtime directory, not the executable).
source "$(dirname "$0")/lib.sh"
L=/var/mobile/tools/bin/less

expect_rc0  "less: binary executable"   "test -x $L"
expect_out  "less: version 668"         "$L --version 2>&1" "less 668"

summary less
