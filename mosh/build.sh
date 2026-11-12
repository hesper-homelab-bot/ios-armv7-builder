#!/bin/bash
# Build mosh 1.4.0 (+ libprotobuf 3.20.3) for armv7 iOS 10.x on Linux.
#
# Prototype port: everything below was learned the hard way and is recorded
# so the next person does not re-derive it.  Order of battle:
#
#   1. host protoc — mosh 1.4.0's release tarball does NOT ship generated
#      .pb.cc/.pb.h (src/protobufs only has the .proto files), so a host
#      protoc is mandatory.  It must be the SAME VERSION as the target
#      libprotobuf: generated code embeds a runtime version check.  apt's
#      protobuf-compiler (3.21) therefore does not mix with libprotobuf
#      3.20.3 — bootstrap protoc from the 3.20.3 source itself:
#         ./configure --prefix=$HOME/ios-tool/protobuf-host --disable-shared
#         make -C src protoc
#   2. libprotobuf — protobuf 3.21+ has no autotools left; 3.20.3 is the
#      last version with a plain `configure --host=...`.  Static only.
#   3. the 64-bit atomic scare did NOT materialize: disassembling arena.o
#      shows clang inlines std::atomic<uint64_t> into a real ldrexd/strexd
#      retry loop on armv7 — it never calls the device's dead
#      ___atomic_load_8 libcall (docs/toolchain.md §4).  Judge by the
#      disassembly ("grep ldrd" false-positives on 64-bit argument moves),
#      not by nm.  at64.o/c8fixed.o from node/patches/shims/ are still
#      linked defensively (cheap) in case libcall form shows up elsewhere.
#   4. mosh's configure probes lie like every other autoconf package under
#      -undefined dynamic_lookup:
#        - HAVE_MACH_ABSOLUTE_TIME 1 (no mach headers here at all) and
#          HAVE_PLEDGE 1 (OpenBSD-only syscall) both have to be #undef'd
#          AFTER configure — but editing config.h directly is undone by
#          config.status regeneration; fix the baked D["..."] values in
#          config.status and re-run ./config.status src/include/config.h
#        - HAVE_PTHREAD: the -lpthread probe fails (wrapper drops it) yet
#          pthreads exist in libSystem — #define HAVE_PTHREAD 1 by hand
#        - configure needs CPPFLAGS="-D_POSIX_C_SOURCE=200809L" on the
#          COMMAND LINE (automake bakes CPPFLAGS into src/Makefile at
#          configure time; `make CPPFLAGS=...` is silently ignored)
#      for the same class of holes in the sysroot itself: xlocale.h/locale_t,
#      posix_memalign, LC_*_MASK (fixed via _POSIX_C_SOURCE), and
#      machine/endian.h forwarding to <endian.h>.
#   5. zlib headers — mosh includes <zlib.h>; the sysroot now carries
#      zlib.h/zconf.h (installed by this repo when libz was built for git).
#   6. locale — iOS has NO locale support: setlocale(LC_ALL,"") returns "C"
#      and nl_langinfo(CODESET) returns garbage ("Sun", probe-verified).
#      mosh 1.4 refuses to run unless is_utf8_locale(); locale_utils.cc is
#      patched to treat the missing locale as UTF-8 on Apple (mosh never
#      transcodes server-side).  Set LANG/LC_* explicitly at both ends.
#
# Usage:
#   export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot \
#          IOS_STUBDIR=$HOME/ios-tool \
#          IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
#          LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
#   ./mosh/build.sh          # -> ../out/mosh-{server,client}
#   ./mosh/make-deb.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
MOSH_VERSION="${MOSH_VERSION:-1.4.0}"
PB_VERSION="${PB_VERSION:-3.20.3}"
CC="$root/tools/cc-wrapper.sh"
CXXW="$HOME/ios-tool/cxx-wrapper.sh"

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:?set IOS_LD64 to the cctools ld64}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

PBROOT="$HOME/ios-tool/protobuf-src/protobuf-$PB_VERSION"
PBHOST="$HOME/ios-tool/protobuf-host"
PBIOS="$HOME/ios-tool/protobuf-ios"
MOSHSRC="${MOSH_SRC:-$HOME/ios-tool/mosh-src/mosh-$MOSH_VERSION}"

# ------------------------------------------------------------- source ----
[ -d "$PBROOT" ] || {
    mkdir -p "$HOME/ios-tool/protobuf-src"
    curl -fsL "https://github.com/protocolbuffers/protobuf/releases/download/v$PB_VERSION/protobuf-cpp-$PB_VERSION.tar.gz" -o /tmp/pb.tar.gz
    tar -C "$HOME/ios-tool/protobuf-src" -xzf /tmp/pb.tar.gz
    mv "$HOME/ios-tool/protobuf-src/protobuf-$PB_VERSION" "$PBROOT" 2>/dev/null || true
}
[ -d "$MOSHSRC" ] || {
    mkdir -p "$HOME/ios-tool/mosh-src"
    curl -fsL "https://github.com/mobile-shell/mosh/releases/download/v$MOSH_VERSION/mosh-$MOSH_VERSION.tar.gz" -o /tmp/mosh.tar.gz
    tar -C "$HOME/ios-tool/mosh-src" -xzf /tmp/mosh.tar.gz
}

# --------------------------------------------------- host protoc ---------
# Same version as the target library, or generated code refuses to load.
if [ ! -x "$PBHOST/bin/protoc" ] && [ ! -x "$PBROOT/src/protoc" ]; then
    ( cd "$PBROOT" \
      && ./configure --prefix="$PBHOST" --disable-shared >/dev/null \
      && make -j"$(nproc)" -C src protoc >/dev/null )
fi
PROTOC="$PBHOST/bin/protoc"
[ -x "$PROTOC" ] || PROTOC="$PBROOT/src/protoc"

# generate mosh's pb sources (they are NOT in the release tarball)
( cd "$MOSHSRC/src/protobufs" && for p in *.proto; do
    "$PROTOC" --cpp_out="$MOSHSRC/src/protobufs" "$p"
done )
# the generated files expect protobuf's own headers on the include path

# ----------------------------------------------- libprotobuf (target) ----
if [ ! -f "$PBIOS/lib/libprotobuf.a" ]; then
    ( cd "$PBROOT" \
      && make distclean >/dev/null 2>&1 || true \
      && CC="$CC" CXX="$CXXW" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
         CPPFLAGS="-D_POSIX_C_SOURCE=200809L" \
         ./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools \
         --disable-shared --enable-static >/dev/null \
      && make -j"$(nproc)" -C src libprotobuf.la >/dev/null )
    # repack the archive as a darwin flat one (ld64 ignores GNU archives)
    n=$( llvm-ar-21 t "$PBROOT/src/.libs/libprotobuf.a" | wc -l )
    [ "$n" -gt 0 ] || { echo "libprotobuf.a has 0 members" >&2; exit 1; }
    tmp=$(mktemp -d)
    ( cd "$PBROOT/src/.libs" && llvm-ar-21 x libprotobuf.a && mv *.o "$tmp/" )
    ( cd "$tmp" && llvm-ar-21 --format=darwin rcs libprotobuf.a *.o )
    mkdir -p "$PBIOS/lib" "$PBIOS/include"
    mv "$tmp/libprotobuf.a" "$PBIOS/lib/"
    cp -a "$PBROOT/src/.libs/../../src"/*.h "$PBIOS/include/" 2>/dev/null || \
        cp -a "$PBROOT/src"/*.h "$PBIOS/include/"
    rm -rf "$tmp"
    echo "==> libprotobuf.a installed to $PBIOS"
fi

# ------------------------------------------------------------- mosh ------
[ -f "$MOSHSRC/src/include/config.h" ] || {
    ( cd "$MOSHSRC" \
      && CC="$CC" CXX="$CXXW" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
         CPPFLAGS="-D_POSIX_C_SOURCE=200809L" \
         ./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools \
         --with-protobuf="$PBIOS" --disable-shared --enable-static >/dev/null )
}

cd "$MOSHSRC"
# bake-value fixes (config.status regeneration undoes direct config.h edits)
sed -i 's|D\["HAVE_MACH_ABSOLUTE_TIME"\]=" 1"|D["HAVE_MACH_ABSOLUTE_TIME"]=" 0"|' config.status
./config.status src/include/config.h >/dev/null
grep -q '#define HAVE_PTHREAD' src/include/config.h || \
    printf '\n#define HAVE_PTHREAD 1\n' >> src/include/config.h
sed -i 's|^#define HAVE_PLEDGE 1$|/* #undef HAVE_PLEDGE -- OpenBSD-only syscall; the probe lied again */|' \
    src/include/config.h

make -j"$(nproc)" >/dev/null

ldid -S src/frontend/mosh-server src/frontend/mosh-client
mkdir -p "$root/out"
cp src/frontend/mosh-server "$root/out/mosh-server"
cp src/frontend/mosh-client "$root/out/mosh-client"
echo "==> $root/out/mosh-server  $root/out/mosh-client"
echo "    next: ./mosh/make-deb.sh"
