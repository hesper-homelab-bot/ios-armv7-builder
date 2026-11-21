#!/bin/bash
# tests/sqlite3.sh -- device acceptance for the sqlite package.
# README table: 3.54.1 (32-bit), WAL, SELECT with WHERE.  Keep the in-memory
# roundtrip (no files touched on the device).
source "$(dirname "$0")/lib.sh"
S=/var/mobile/tools/bin/sqlite3

expect_out "sqlite3: version 3.54.1"    "$S --version" "3.54.1"
expect_out "sqlite3: create+sum roundtrip" \
    "$S :memory: 'CREATE TABLE t(x); INSERT INTO t VALUES(40),(2); SELECT sum(x) FROM t;'" "42"

summary sqlite3
