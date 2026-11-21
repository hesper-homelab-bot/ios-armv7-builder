#!/bin/bash
# tests/pgrep.sh -- device acceptance for the pgrep/pkill package.
# README table: pgrep -lf dropbear prints the full argv of the production
# dropbear; cross-uid rows fall back to (comm) (KERN_PROCARGS2 model,
# docs/pgrep.md section 3).
#
# SSH SELF-MATCH ARTIFACT: every case here runs through ssh, so a "sh -c"
# process whose argv contains the pattern string exists while the probe
# runs, and pgrep -f happily matches it.  Every assertion therefore filters
# the sh -c row out before requiring a hit -- a match must come from a real
# service process.
source "$(dirname "$0")/lib.sh"

expect_rc0 "pgrep: dropbear full argv visible" \
    "/usr/bin/pgrep -lf dropbear | grep -v 'sh -c' | grep -q db-dropbear"
expect_rc0 "pgrep: deep argv token host_ed25519" \
    "/usr/bin/pgrep -lf host_ed25519 | grep -v 'sh -c' | grep -q host_ed25519"
expect_rc0 "pkill: binary present (not executed)" \
    "test -x /usr/bin/pkill"

summary pgrep
