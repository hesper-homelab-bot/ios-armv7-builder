#!/bin/bash
# tests/quickjs.sh -- device acceptance for the quickjs4 package.
# README/docs: phase-1 smoke (qjs -e 'print(40+2)' -> 42) plus the JSON,
# regexp, float-precision and ES2023 samples verified at productization.
source "$(dirname "$0")/lib.sh"
Q=/var/mobile/tools/bin/qjs

expect_out  "quickjs: eval smoke"           "$Q -e 'print(40+2)'" "42"
expect_out  "quickjs: JSON.stringify"       "$Q -e 'print(JSON.stringify({a:[1,2],b:\"x\"}))'" '{"a":[1,2],"b":"x"}'
expect_out  "quickjs: regexp exec group"    "$Q -e 'print(/q(u+)ick/.exec(\"quuick\")[1])'" "uu"
expect_out  "quickjs: float semantics"      "$Q -e 'print((0.1+0.2).toFixed(1))'" "0.3"
expect_out  "quickjs: ES2023 optional chaining" \
            "$Q -e 'const o={p:{v:5}}; print(o?.p?.v ?? -1, o?.q?.v ?? -1)'" "5 -1"

summary quickjs
