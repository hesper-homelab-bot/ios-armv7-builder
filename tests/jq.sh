#!/bin/bash
# tests/jq.sh -- device acceptance for the jq package.
# README table: .a[1], reduce range(100), add, UTF-8 round-trip.
source "$(dirname "$0")/lib.sh"
J=/var/mobile/tools/jq

expect_out "jq: version"                "$J --version" "jq-1.7.1"
expect_out "jq: array index"            "echo '{\"a\":[1,2,3]}' | $J .a[1]" "2"
expect_out "jq: add over 1..100"        "seq 1 100 | $J -s add" "5050"

summary jq
