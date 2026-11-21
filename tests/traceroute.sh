#!/bin/bash
# tests/traceroute.sh -- device acceptance for the traceroute4 package
# (setuid 4755, runs as mobile).  README table: traceroute -n -m 1 <gateway>
# reaches the gateway in one hop.  The gateway is read from our own route,
# never hardcoded.
source "$(dirname "$0")/lib.sh"
T=/usr/bin/traceroute

GW='$(/var/mobile/tools/ifconfig/route -n get default | awk "/gateway/{print \$2}")'
expect_out "traceroute: gateway in 1 hop" \
    "$T -n -m 1 $GW" " 1  "

summary traceroute
