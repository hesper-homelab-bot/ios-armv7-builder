#!/bin/bash
# tests/tmux.sh -- device acceptance for the tmux package.
# README table: "tmux 3.8 -- sessions, panes, detach/reattach"; here we keep
# the read-only smoke level (binary + version).
source "$(dirname "$0")/lib.sh"

expect_rc0  "tmux: binary executable"   "test -x /usr/bin/tmux"
expect_out  "tmux: -V reports 3.8"      "/usr/bin/tmux -V" "tmux 3.8"

summary tmux
