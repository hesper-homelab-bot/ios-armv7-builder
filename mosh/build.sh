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

# mosh's configure locates OpenSSL through PKG_CHECK_MODULES([OpenSSL],
# [openssl]) -- i.e. pkg-config, not --with-openssl.  Without this path
# pkg-config happily answers with the HOST OpenSSL (3.5.5), whose
# AC_CHECK_LIB([crypto],[AES_encrypt]) probe cannot be run at all when
# cross-compiling, so the check fails and configure aborts with:
#     configure: error: found OpenSSL without AES support
# Point pkg-config at our armv7 OpenSSL 4.0.3 (the same static libs nginx
# links); _AES_encrypt and _EVP_aes_128_ocb are both present in it
# (llvm-nm-21 --defined-only .../libcrypto.a | grep AES).
OSSL_DIR="${OSSL_DIR:-$HOME/ios-tool/openssl-src/openssl-4.0.3}"
# PBIOS is needed by the pkg-config block below; it is also used further down
# for the libprotobuf install prefix, so it is defined here once.
PBIOS="${PBIOS:-$HOME/ios-tool/protobuf-ios}"
[ -f "$OSSL_DIR/lib/pkgconfig/openssl.pc" ] || {
    echo "no openssl.pc under $OSSL_DIR (set OSSL_DIR)" >&2; exit 1; }
# PKG_CONFIG_LIBDIR (not just PATH) is what silences the host packages: it
# replaces the built-in search path instead of appending to it.  Both of our
# cross-built dependencies must be listed, because mosh configures OpenSSL
# *and* protobuf through pkg-config -- with only openssl here, configure
# aborts on the next check with "Package 'protobuf' not found".
export PKG_CONFIG_PATH="$OSSL_DIR/lib/pkgconfig:$PBIOS/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PKG_CONFIG_LIBDIR="$OSSL_DIR/lib/pkgconfig:$PBIOS/lib/pkgconfig"

PBROOT="$HOME/ios-tool/protobuf-src/protobuf-$PB_VERSION"
PBHOST="$HOME/ios-tool/protobuf-host"
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
    # The release tag carries a "mosh-" prefix, NOT "v": the correct URL is
    #   .../releases/download/mosh-1.4.0/mosh-1.4.0.tar.gz
    # Using .../v1.4.0/... returns HTTP 404, which curl -f turns into exit 22
    # (the "exit=22" seen on a re-run after the source tree was removed).
    curl -fsL --retry 3 --retry-delay 2 --connect-timeout 20 \
        "https://github.com/mobile-shell/mosh/releases/download/mosh-$MOSH_VERSION/mosh-$MOSH_VERSION.tar.gz" -o /tmp/mosh.tar.gz
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
[ -x "$PROTOC" ] || { echo "no usable protoc at $PBHOST/bin/protoc" >&2; exit 1; }

# mosh's configure finds protoc with AC_PATH_PROG, i.e. through $PATH only
# (configure.ac has no --with-protoc option).  Our protoc lives in the
# protobuf-host prefix, which is deliberately not on $PATH, so a bare
# ./configure dies with:
#     configure: error: cannot find protoc, the Protocol Buffers compiler
# AC_PATH_PROG honours a pre-set environment variable of the same name, so
# exporting PROTOC is the supported way to point configure at our copy.
export PROTOC

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
# The AES capability probes cannot be answered by linking here: configure's
# AC_CHECK_LIB([crypto],[AES_encrypt]) emits a bare `-lcrypto`, and the
# cross ld64 has no such library in its search path, so both checks report
# "no" and configure aborts with:
#     configure: error: found OpenSSL without AES support
# The symbols do exist in our static libcrypto (verified: llvm-nm-21
# --defined-only .../libcrypto.a | grep _AES_encrypt, and an explicit
# `cc-wrapper.sh t.c $OSSL/libcrypto.a -lz` links clean).  Pre-seeding the
# autoconf cache variables is the supported way to state a fact the probe
# cannot establish; mosh then links the real archive through CRYPTO_LIBS.
export ac_cv_lib_crypto_AES_encrypt=yes
export ac_cv_lib_crypto_EVP_aes_128_ocb=yes

# _XOPEN_SOURCE=700 must accompany _POSIX_C_SOURCE: mosh needs the POSIX
# feature macros, but the sysroot's `wchar.h` guards wcwidth() with
#     #if defined(_XOPEN_SOURCE) || defined(_GNU_SOURCE) || defined(_BSD_SOURCE)
# because wcwidth is an XSI extension, not POSIX.  With _POSIX_C_SOURCE
# alone the declaration disappears and the build dies in terminal.cc:
#     error: use of undeclared identifier 'wcwidth'
# Verified with a one-line probe: <wchar.h> + wcwidth compiles under
# "-D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700" and fails under
# _POSIX_C_SOURCE alone.  700 is POSIX.1-2008 + XSI, matching the 200809L
# level already requested.  Both macros are baked into src/Makefile by
# automake, so they must be on configure's command line (see NOTE below).
# _DNDEBUG is REQUIRED, and must match how libprotobuf.a was built.
#
# protobuf's configure adds -DNDEBUG to its own CXXFLAGS by default
# (configure.ac: "end users who don't want these checks, so add -DNDEBUG
# by default"), so our libprotobuf.a was compiled with NDEBUG: in
# metadata_lite.h the destructor took the inline branch and no archive
# member defines the out-of-line form.  Consumers compiled WITHOUT NDEBUG
# take the header's other branch -- `~InternalMetadata();` declared
# out-of-line "because the GOOGLE_DCHECK produces a lot of code" -- and
# reference an external symbol that nothing provides.  The cc wrapper links
# with -undefined dynamic_lookup, so the hole passes the link and only
# detonates at runtime, on the first message destruction:
#
#     dyld: Symbol not found: __ZN6google8protobuf8internal16InternalMetadataD1Ev
#     Application Specific Information: crashed on child side of fork pre-exec
#
# (Crash report mosh-server-old-2026-11-13-093543.ips; both yesterday's and
# today's binaries carried it -- a latent fault, not a rebuild regression.
# The inline NDEBUG destructor is semantically identical to the out-of-line
# one, minus a debug-only GOOGLE_DCHECK.)  Defining NDEBUG here selects the
# inline branch in mosh's TUs too, making the binary self-contained and
# matching the library's ABI branch.  Side effect: mosh's plain assert()s
# compile out -- standard release behaviour; its fatal_assert error paths
# are mosh's own macro and stay active.
MOSH_CPPFLAGS="-D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -DNDEBUG"

# zlib must resolve to the REAL static archive at configure time.
#
# The sysroot carries zlib.h/zconf.h but NO libz.a (only the headers were
# installed when libz was cross-built for git), and mosh's configure tests
# zlib with AC_CHECK_LIB([z],[uncompress]) -- which cannot fail here because
# the cc wrapper links with -undefined dynamic_lookup: the test "link"
# succeeds even with no library at all, configure concludes zlib exists and
# bakes bare `-lz` into the Makefiles, and the final link leaves uncompress/
# deflate/inflate undefined.  The result is a binary that dies at launch:
#
#     Termination Description: DYLD, Symbol not found: _uncompress
#       Referenced from: /var/mobile/tools/bin/mosh-server.real
#     Exception Type: EXC_CRASH (SIGABRT)          (10:37:42, via Termius)
#
# Point -L at the zlib 1.3.1 build tree (the same archive nginx links
# statically) so the configure probe and the final link both resolve it for
# real.  This is the same wall as nginx's "explicit archives last on the
# link line" (toolchain.md §2) -- under -undefined dynamic_lookup, ANY
# missing library is silently accepted at build time and only detonates on
# the device.
ZLIB_DIR="$HOME/ios-tool/zlib-src/zlib-1.3.1"
[ -f "$ZLIB_DIR/libz.a" ] || { echo "missing $ZLIB_DIR/libz.a" >&2; exit 1; }
MOSH_LDFLAGS="-L$ZLIB_DIR"

[ -f "$MOSHSRC/src/include/config.h" ] || {
    ( cd "$MOSHSRC" \
      && CC="$CC" CXX="$CXXW" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
         CPPFLAGS="$MOSH_CPPFLAGS" LDFLAGS="$MOSH_LDFLAGS" \
         ./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools \
         --with-protobuf="$PBIOS" --disable-shared --enable-static \
         --with-crypto-library=openssl >/dev/null )
}

cd "$MOSHSRC"
python3 "$root/mosh/patch-mosh.py"   # early detach + locale (see patches file)

# --------------------------------------------- header corrections ----
# These must be applied to config.h.in, the *template*, before config.status
# turns it into config.h.
#
# Why not fix config.h directly: src/include/Makefile carries autoconf's
# header rules,
#     config.h: stamp-h1
#     stamp-h1: $(srcdir)/config.h.in $(top_builddir)/config.status
#             cd $(top_builddir) && $(SHELL) ./config.status src/include/config.h
# and config.status ends up newer than stamp-h1, so the first make re-runs
# config.status and rewrites config.h from the baked D[...] values.  A sed on
# config.h is therefore reverted mid-build -- which is exactly why an earlier
# attempt kept dying with "use of undeclared identifier 'pledge'" however the
# fix was worded.  config.h.in survives because autoheader only regenerates it
# when configure.ac/aclocal.m4 are newer (they are from 2022), and anything in
# the template that is not a bare "#undef NAME" is copied through untouched.
CFG_IN="$MOSHSRC/src/include/config.h.in"

# 1. HAVE_PLEDGE must be *undefined*, not 0: mosh's call sites use
#        #ifdef HAVE_PLEDGE
#    so even "#define HAVE_PLEDGE 0" compiles the pledge() call in and the
#    build fails at mosh-server.cc:615 / stmclient.cc:431.  The probe reports 1
#    only because it *compiles* a test program and a declaration was enough --
#    pledge() is an OpenBSD syscall that iOS does not have.  Turning the
#    template's "#undef HAVE_PLEDGE" into a comment stops config.status from
#    substituting the baked value back in.
sed -i 's|^#undef HAVE_PLEDGE$|/* #undef HAVE_PLEDGE -- OpenBSD-only syscall, absent on iOS.  Must stay undefined: mosh uses #ifdef, so a value of 0 would still compile the call in. */|' \
    "$CFG_IN"

# 2. HAVE_PTHREAD has no "#undef" line at all (the -lpthread link probe fails
#    because the cc wrapper drops the flag, so configure writes nothing).  iOS
#    has pthreads inside libSystem, so the define is appended to the template.
grep -q '^#define HAVE_PTHREAD' "$CFG_IN" || cat >> "$CFG_IN" <<'HPTHREAD'

/* iOS has pthreads in libSystem; the -lpthread probe cannot see them. */
#define HAVE_PTHREAD 1
HPTHREAD

# 3. QUASH the automake regeneration chain.  The tarball's mtimes differ by
#    seconds (configure.ac a hair newer than aclocal.m4), so the first make
#    fires aclocal -> autoconf -> config.status --recheck -> autoheader --
#    and autoheader REGENERATES config.h.in from configure.ac, discarding
#    the two corrections above, then the recheck re-probes pledge and re-bakes
#    HAVE_PLEDGE=1 (observed 2026-11-13 full rebuild).  Equal mtimes quiet
#    every rule (make only rebuilds on strictly-newer prerequisites); and if
#    a regeneration happens anyway, the template corrections survive by
#    design (they live in the template, which is copied through verbatim).
touch "$MOSHSRC/configure.ac" "$MOSHSRC/aclocal.m4" "$MOSHSRC/configure" \
      "$CFG_IN" "$MOSHSRC/aminclude_static.am" 2>/dev/null || true
# Makefile.in depends on configure.ac too -- every one of them, in every
# subdirectory -- so they all get the same instant as well, or automake
# fires and fails (observed 2026-11-13).
find "$MOSHSRC" -name "Makefile.in" -exec touch {} + 2>/dev/null || true

# 4. HAVE_MACH_ABSOLUTE_TIME is a baked value rather than a template line: the
#    sysroot has the mach headers the probe looks for but no linkable
#    mach_absolute_time(), and configure's own failed link already stores " 0".
#    Rewriting the baked value keeps it honest if configure is ever re-run.
sed -i 's|D\["HAVE_MACH_ABSOLUTE_TIME"\]=" 1"|D["HAVE_MACH_ABSOLUTE_TIME"]=" 0"|' config.status

# Now generate config.h from the corrected template.
./config.status src/include/config.h >/dev/null

# Fail loudly if a correction did not survive, instead of rediscovering it
# several hundred lines later in a compile log.
grep -qE '^#define HAVE_PLEDGE' src/include/config.h && {
    echo "HAVE_PLEDGE is defined in config.h -- pledge() will not compile" >&2; exit 1
}
grep -q '^#define HAVE_PTHREAD 1$' src/include/config.h || {
    echo "HAVE_PTHREAD correction missing from config.h" >&2; exit 1
}

# NOTE: protobuf/mosh both need feature macros; configure must receive
# CPPFLAGS=-D_POSIX_C_SOURCE=200809L on its COMMAND LINE (automake bakes
# CPPFLAGS into src/Makefile at configure time; `make CPPFLAGS=...` is
# silently ignored).  Both configure invocations above already pass it.

# zlib: link the EXPLICIT archive, not -lz.
#
# Probe-verified (2026-11-13): `cc-wrapper.sh t.c -L$ZLIB_DIR -lz` leaves
# _uncompress undefined, while naming $ZLIB_DIR/libz.a directly resolves it
# -- the -L+/-lz search does not survive the wrapper chain.  nginx dodged
# this by putting the archive path directly on its link line (wall #4:
# explicit archives).  The device-side symptom of leaving it broken:
#     dyld: Symbol not found: _uncompress  → SIGABRT at launch, via Termius
#
# AFTER sed-ing the generated Makefiles they must be touched: make knows
#     Makefile: Makefile.in $(top_builddir)/config.status
# and config.status is minutes old while Makefile.in is from the 2022
# tarball, so the first make would regenerate every Makefile from
# config.status and wipe the edit -- the same trap as editing config.h
# directly (see the header corrections above).
# Settle any pending regeneration FIRST (config.status re-runs and rewrites
# every Makefile), THEN apply the -lz fix and make the Makefiles newer than
# config.status so the build's own dependency check does not undo it.
./config.status >/dev/null

find "$MOSHSRC/src" -name Makefile \
    -exec sed -i "s|-lz\b|$ZLIB_DIR/libz.a|g" {} \; \
    -exec touch {} \;

make -j"$(nproc)" >/dev/null

# Prove the correction survived the build, rather than trusting the ordering.
grep -qE '^#define HAVE_PLEDGE' src/include/config.h && {
    echo "make regenerated config.h and restored HAVE_PLEDGE" >&2; exit 1
}

ldid -S src/frontend/mosh-server src/frontend/mosh-client
mkdir -p "$root/out"
cp src/frontend/mosh-server "$root/out/mosh-server"
cp src/frontend/mosh-client "$root/out/mosh-client"

# Post-link audit: every undefined symbol must be provably provided by the
# device (tbd stubs + device-verified list) or be device-libc++.  This is
# what would have caught the setproctitle / InternalMetadata / uncompress
# dyld deaths at build time instead of on the device (toolchain.md §9/§10).
for b in mosh-server mosh-client; do
    "$root/tools/check-undefined.sh" "$root/out/$b"
done
echo "==> $root/out/mosh-server  $root/out/mosh-client"
echo "    next: ./mosh/make-deb.sh"
