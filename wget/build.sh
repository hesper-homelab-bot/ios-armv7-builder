#!/bin/bash
# Build GNU wget (verified with 1.25.0) for armv7 iOS 10.x on Linux.
#
# Modelled on ../curl/build.sh: same sysroot, same compiler wrapper, same
# class of problems.  See ../README.md for the full Darwin ABI story, and
# ios-config.site in this directory for why the configure probes all lie.
#
# Depends on an OpenSSL built by ../openssl/build.sh -- wget links libssl.a
# and libcrypto.a statically, so there is no runtime dependency on a shared
# OpenSSL and nothing in /usr is touched.
#
# Usage:
#   LD64=/path/to/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
#   LD64_LIBS=/path/to/x-libdispatch/lib:/path/to/x-tapi/lib \
#   ./build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
WGET_VERSION="${WGET_VERSION:-1.25.0}"
SRC="${WGET_SRC:-$HOME/ios-tool/wget-src/wget-$WGET_VERSION}"
OSSL="${OSSL:-$HOME/ios-tool/openssl-src/openssl-4.0.3}"
PREFIX="${PREFIX:-/var/mobile/tools}"

[ -d "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
[ -f "$OSSL/libssl.a" ] || { echo "build OpenSSL first (openssl/build.sh)" >&2; exit 1; }
export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }

# libSystem.tbd lives next to the toolchain in ~/ios-tool, not in this repo
# (the repo is public; the Apple-built stub is not redistributed).
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="${LD64_LIBS:-}:${LD_LIBRARY_PATH:-}"
export CROSS_TOP="$root/tmp" CROSS_SDK=sysroot

# configure's link tests always "succeed" here because the wrapper links with
# -undefined dynamic_lookup, and its runtime tests cannot execute while
# cross-compiling.  ios-config.site corrects both kinds of lie.  It must be
# a config.site rather than --cache-file: autoconf rewrites the cache file at
# the end of every run, so hand-edited cache values survive only one run.
export CONFIG_SITE="$here/ios-config.site"

cd "$SRC"
make distclean >/dev/null 2>&1 || true

# OpenSSL 4 dropped the SSLv3 (and SSLv2) entry points entirely, but wget
# guards its call with #ifndef OPENSSL_NO_SSL3_METHOD -- a macro Apple's and
# old OpenSSL's headers defined and modern OpenSSL does not, so the call is
# compiled in and fails with "call to undeclared function
# 'SSLv3_client_method'".  The option name still exists in wget's
# --secure-protocol parsing, so the call site stays; it just needs to be
# switched off at the preprocessor level.
EXTRA_CFLAGS="-DOPENSSL_NO_SSL3_METHOD=1 -DOPENSSL_NO_SSL2=1"

CC="$root/tools/cc-wrapper.sh" AR="$root/tools/darwin-ar" \
RANLIB="$root/tools/darwin-ranlib" \
CFLAGS="$EXTRA_CFLAGS" \
./configure --host=armv7-apple-darwin --prefix="$PREFIX" \
    --disable-shared --enable-static \
    --with-ssl=openssl --with-libssl-prefix="$OSSL" \
    --without-zlib --without-libpsl --without-libiconv-prefix \
    --without-libintl-prefix --without-libunistring-prefix \
    --disable-nls --disable-iri --disable-pcre --disable-pcre2 \
    --disable-ntlm --disable-opie --disable-xattr \
    --disable-threads --disable-largefile \
    --enable-cross-guesses=conservative \
    >/dev/null

# ---------------------------------------------------------------------------
# gnulib's posix_spawn module has to go.  This is the single most stubborn
# part of porting wget, so the whole story is recorded here.
#
# gnulib ships a from-scratch implementation (lib/spawni.c and friends) that it
# enables whenever it decides the system one is inadequate.  On iOS that
# implementation cannot possibly work:
#
#   * it is built on vfork(), setresuid()/setresgid() and confstr(), none of
#     which iOS 10 exports (verified on the device: a program calling vfork()
#     prints its line before the call and then dies silently, the classic dyld
#     "Symbol not found" abort);
#   * it reads musl's by-value posix_spawnattr_t / posix_spawn_file_actions_t
#     (80 and 72 bytes on armv7), while Darwin uses 4-byte opaque pointers.
#
# The device has a perfectly good posix_spawn of its own -- verified on an
# iPad 4 by calling posix_spawnp() with a file-actions addopen: rc=0, the
# child ran, stdout was redirected correctly.  So the goal is to keep the
# system implementation and drop gnulib's.
#
# Why that is not a one-line change: four layers all have to agree.
#
#   1. lib/Makefile -- automake expands the replacement objects through
#      am__append_<N> / am__objects_<N> variables (79..92 here).
#   2. am__libgnu_a_SOURCES_DIST -- the same file names are ALSO listed
#      literally, on their own line, so blanking the appends alone is not
#      enough (this is what silently kept working after every earlier attempt).
#   3. config.status -- running "./config.status lib/Makefile" regenerates the
#      file from the values baked in at configure time and silently reverts
#      edits (1) and (2).  The values have to be corrected there too.
#   4. lib/spawn.h and sysroot-overlay/usr/include/spawn.h -- gnulib generates
#      its own <spawn.h> into lib/, which is on the include path ahead of the
#      sysroot's.  That header, controlled by GNULIB_POSIX_SPAWN rather than
#      REPLACE_POSIX_SPAWN, unconditionally renames the calls and declares its
#      own fat structs.  Leaving it in place produced undefined symbols named
#      rpl_posix_spawnp, rpl_posix_spawn_file_actions_init and
#      rpl_posix_spawn_file_actions_adddup2 in the final binary -- calls to
#      functions that no longer exist, waiting to abort in dyld the first time
#      --use-askpass is used.
#
# gnulib itself should be able to express this, but every route through its
# logic forces the replacement on: posix_spawn exists (so not HAVE_,) yet
# posix_spawn_file_actions_addchdir_np does not, and that alone sets
# REPLACE_POSIX_SPAWN=1.  Darwin really does lack addchdir_np, so the check
# cannot be satisfied while telling the truth.

SPAWN_VARS="REPLACE_POSIX_SPAWN REPLACE_POSIX_SPAWN_FILE_ACTIONS_ADDCLOSE \
REPLACE_POSIX_SPAWN_FILE_ACTIONS_ADDDUP2 REPLACE_POSIX_SPAWN_FILE_ACTIONS_ADDOPEN"
SPAWN_APPENDS="79 80 81 82 83 84 85 86 87 88 89 90 91 92"
SPAWN_SOURCES="spawn.c spawni.c spawn_faction_addchdir.c spawn_faction_addclose.c \
spawn_faction_adddup2.c spawn_faction_addopen.c spawn_faction_destroy.c \
spawn_faction_init.c spawnattr_destroy.c spawnattr_init.c spawnattr_setflags.c \
spawnattr_setpgroup.c spawnattr_setsigmask.c spawnp.c"

# (3) Correct the values baked into config.status first, so that a later
#     regeneration cannot undo the work below.
for v in $SPAWN_VARS; do
    sed -i "s|^S\[\"$v\"\]=\"1\"|S[\"$v\"]=\"0\"|"            config.status
    sed -i "s|^D\[\"$v\"\]=\" 1\"|D[\"$v\"]=\" 0\"|"          config.status
done

# (1) Regenerate lib/Makefile from the corrected values, then blank the
#     automake variables that expand the replacement sources.
./config.status lib/Makefile >/dev/null 2>&1
for n in $SPAWN_APPENDS; do
    sed -i "s|^am__append_$n = .*$|am__append_$n =|"   lib/Makefile
    sed -i "s|^am__objects_$n = .*$|am__objects_$n =|" lib/Makefile
done

# (2) Remove the sources from am__libgnu_a_SOURCES_DIST.  They are listed as
#     bare file names inside a backslash-continued list, so the tokens are
#     dropped one at a time and the continuations are kept balanced.
python3 - "$SPAWN_SOURCES" <<'PY'
import sys
srcs = set(sys.argv[1].split())
p = 'lib/Makefile'
lines = open(p).read().split('\n')
start = next(i for i, l in enumerate(lines) if l.startswith('am__libgnu_a_SOURCES_DIST'))
end = start
while lines[end].rstrip().endswith('\\'):
    end += 1
for i in range(start, end + 1):
    toks = [t for t in lines[i].split() if t not in srcs]
    if not toks:
        # Drop the now-empty line entirely to avoid emitting a bare '\\'.
        lines[i] = None
        continue
    lines[i] = '\t' + ' '.join(toks) + (' \\' if i < end else '')
open(p, 'w').write('\n'.join(l for l in lines if l is not None))
PY

# (4) Drop gnulib's generated <spawn.h> so that wget's own source picks up the
#     sysroot's Darwin-ABI version, and remove the rule that would rebuild it.
rm -f lib/spawn.h

# The sed commands above rewrote config.status, so its mtime is now newer than
# every generated Makefile's.  Every Makefile in this tree carries the automake
# rule
#
#     Makefile: $(srcdir)/Makefile.in $(top_builddir)/config.status
#             ... $(SHELL) ./config.status
#
# so make would consider them all out of date and re-run ./config.status, which
# recreates them (including lib/Makefile) from the very values this whole block
# just corrected away -- the reason every earlier attempt silently reverted.
# Touch them all last so make leaves them alone.
find . -name Makefile -print0 | xargs -0 touch

make -j"$(nproc)" >/dev/null

ldid -S src/wget
mkdir -p "$root/out"
cp src/wget "$root/out/wget-$WGET_VERSION-armv7"
echo "==> $root/out/wget-$WGET_VERSION-armv7"
echo "    install: scp to $PREFIX/wget, then ldid -S on the device"
echo "    set SSL_CERT_FILE=/etc/ssl/cert.pem for HTTPS"
