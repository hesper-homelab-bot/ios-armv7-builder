#!/bin/bash
# tests/ifconfig.sh -- device acceptance for the ifconfig4 package
# (network_cmds-457: ifconfig + route + arp + ndp).
# README table: ifconfig -a lists en0 with media/status; route -n get default
# resolves the en0 gateway.  Read-only forms only.
source "$(dirname "$0")/lib.sh"
D=/var/mobile/tools/ifconfig

expect_out "ifconfig: -a lists en0"     "$D/ifconfig -a" "en0"
expect_out "ifconfig: en0 has flags"    "$D/ifconfig en0" "flags"
expect_out "route: default gateway"     "$D/route -n get default" "gateway:"

summary ifconfig
