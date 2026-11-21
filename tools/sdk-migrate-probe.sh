#!/bin/bash
# SDK-mode build probe for one package: rc + gate result.
set -uo pipefail
pkg="$1"
cd ~/ios-armv7-builder/"$pkg" || exit 9
export IOS_SYSROOT=$HOME/ios-tool/iPhoneOS10.3.sdk
export IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld
export IOS_STUBDIR=$HOME/ios-tool
export LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
export OSSL=$HOME/ios-tool/openssl-src/openssl-4.0.3
if bash ./build.sh >/tmp/sdkprobe-$pkg.log 2>&1; then
    bin=$(ls -t ../out/*-armv7 2>/dev/null | grep -i "$pkg" | head -1)
    gate=$([ -n "$bin" ] && ../tools/check-undefined.sh "$bin" 2>&1 | tail -1 || echo "no-binary")
    echo "PASS $pkg :: $gate"
else
    echo "FAIL $pkg :: $(tail -2 /tmp/sdkprobe-$pkg.log | head -1)"
fi
