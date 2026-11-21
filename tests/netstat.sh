#!/bin/bash
# tests/netstat.sh -- device acceptance for the netstat4 package.
# README table: -a/-t/-u/-r/-i all pass; routes show "default" via en0;
# 13 interfaces.  Read-only forms only.
source "$(dirname "$0")/lib.sh"
N=/var/mobile/tools/bin/netstat

expect_out "netstat: -r has default route"  "$N -r" "default"
expect_out "netstat: -i lists en0"          "$N -i" "en0"

summary netstat
