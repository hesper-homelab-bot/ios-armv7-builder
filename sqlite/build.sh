#!/bin/bash
# Build the SQLite command-line shell + library for armv7 iOS 10.x on Linux.
#
# Deliberately does NOT run configure.  The task book allows either route, and
# the direct-amalgamation route is chosen here for the same reason git uses a
# hand-written config.mak: on this target every autoconf probe lies.
#
#   * Link tests "pass" for anything at all, because cc-wrapper links with
#     -undefined dynamic_lookup; a probe can never discover that iOS 10 lacks
#     a symbol.
#   * Run tests cannot run while cross-compiling, so AC_RUN_IFELSE falls back
#     to a pessimistic guess -- and SQLite's are keyed on glibc/BSD FILE
#     internals the musl-derived sysroot does not have.
#   * sqlite's configure also sniffs for functions like localtime_r,
#     usleep, fdatasync ... and would answer "yes" to whatever the link test
#     says, not to what the device actually exports.
#
# The amalgamation is two translation units (sqlite3.c + shell.c) plus a
# generated sqlite3.h; a plain cc-wrapper invocation over those is both
# simpler and more honest than a configure run whose output we would have to
# hand-correct anyway.  Everything is static, so the package has no runtime
# library dependency at all (not even zlib: see the note about -lz below).
#
# Usage:
#   export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot \
#          IOS_STUBDIR=$HOME/ios-tool \
#          IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
#          LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
#   ./sqlite/build.sh          # -> ../tmp/sqlite-staging
#   ./sqlite/make-deb.sh       # -> ../out/sqlite3_<ver>-1_iphoneos-arm.deb
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
SQLITE_VERSION="${SQLITE_VERSION:-3540100}"          # 3.54.1 (NNNEEPP spelling)
SQLITE_VER_DOTTED="${SQLITE_VER_DOTTED:-3.54.1}"
SRC="${SQLITE_SRC:-$HOME/ios-tool/sqlite-src/sqlite-autoconf-$SQLITE_VERSION}"
STAGING="${STAGING:-$root/tmp/sqlite-staging}"
PREFIX="/var/mobile/tools"
CC="$root/tools/cc-wrapper.sh"

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:?set IOS_LD64 to the cctools ld64}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ------------------------------------------------------------------ source --
if [ ! -f "$SRC/sqlite3.c" ]; then
    mkdir -p "$(dirname "$SRC")"
    echo "==> fetching sqlite-autoconf-$SQLITE_VERSION"
    # sqlite.org is the canonical source and is reachable from this host;
    # GitHub (which several mirrors live on) is not reachable from the
    # *device* network and is not needed here.
    curl -fL --max-time 300 "https://sqlite.org/2026/sqlite-autoconf-$SQLITE_VERSION.tar.gz" \
        -o /tmp/sqlite-autoconf.tar.gz
    tar -C "$(dirname "$SRC")" -xzf /tmp/sqlite-autoconf.tar.gz
fi
[ -f "$SRC/sqlite3.c" ] || { echo "missing amalgamation in $SRC" >&2; exit 1; }

cd "$SRC"

# ------------------------------------------------------------------ flags ---
# Feature set: exactly the extras that ship enabled in the upstream
# sqlite-autoconf build (so the shell behaves like a normal desktop sqlite3),
# minus anything that needs a library iOS does not have.
#
#   SQLITE_ENABLE_FTS5    full-text search v5  (pure C, no dependency)
#   SQLITE_ENABLE_RTREE   R*tree index         (pure C, no dependency)
#   SQLITE_ENABLE_COLUMN_METADATA  .schema/table_info helpers
#   SQLITE_ENABLE_DBSTAT_VTAB      dbstat virtual table
#   SQLITE_ENABLE_MATH_FUNCTIONS   sin/cos/... SQL functions
#   SQLITE_ENABLE_JSON1            core in 3.38+, kept for clarity
#   SQLITE_THREADSAFE=0            single-threaded shell; removes the mutex
#                                  layer entirely.  This is also the safest
#                                  answer to docs/toolchain.md §4: the device
#                                  libcall ___atomic_load_8 is an empty
#                                  function, so any 64-bit atomic *read*
#                                  silently returns garbage.  With
#                                  THREADSAFE=0 sqlite takes no atomics at
#                                  all on the hot paths.
#
# SQLITE_OMIT_LOAD_EXTENSION: dynamic loading would go through dlopen, which
# exists on iOS but cannot load unsigned code; omitting it also drops the
# dlopen/dlsym requirements from the link.
#
# NOTE on -lz: do NOT add it.  cc-wrapper silently drops -lz (it sits in the
# "all inside libSystem on Darwin" list, which is true on macOS but NOT on
# iOS 10, where zlib lives in a separate libz.dylib).  sqlite only needs zlib
# when SQLITE_HAVE_ZLIB is defined, which it is not here, so the shell has no
# zlib dependency -- but if that ever changes, link $ZLIB/libz.a as an
# explicit archive object (see git/build.sh) instead of using -lz.
CFLAGS_COMMON="-Os -mthumb -march=armv7 -fno-common -DSQLITE_THREADSAFE=0 \
-DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_JSON1 \
-DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_DBSTAT_VTAB \
-DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_UNLOCK_NOTIFY=0 \
-DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_DEPRECATED \
-DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DQS=0 \
-DSQLITE_MAX_MMAP_SIZE=0 -DSQLITE_OMIT_PROGRESS_CALLBACK=0"

echo "==> compiling sqlite3.c (amalgamation, $(wc -l < sqlite3.c) lines)"
$CC $CFLAGS_COMMON -c sqlite3.c -o sqlite3.o
echo "==> compiling shell.c"
$CC $CFLAGS_COMMON -DSQLITE_SHELL_HAVE_READLINE=0 -c shell.c -o shell.o

# One static archive is produced as well so the .deb can ship a libsqlite3.a
# for on-device C builds.  It MUST be a Darwin-format archive: ld64 silently
# ignores GNU archives (docs/toolchain.md §2), and llvm-ar writes GNU by
# default -- hence the explicit --format=darwin and the member-count check.
llvm-ar-21 --format=darwin rcs libsqlite3.a sqlite3.o
members="$(llvm-ar-21 t libsqlite3.a | wc -l)"
[ "$members" -gt 0 ] || { echo "libsqlite3.a conversion produced 0 members" >&2; exit 1; }
echo "==> libsqlite3.a: $members member(s)"

echo "==> linking sqlite3"
# sqlite3.o is passed as an explicit object on the link line.  Passing it as
# -lsqlite3 with -L. would work too, but the explicit form is what the task
# book's wall #2 asks for and is immune to any future -l* filtering in the
# wrapper.
$CC -O2 -o sqlite3 sqlite3.o shell.o

# ----------------------------------------------------------------- install --
rm -rf "$STAGING"
mkdir -p "$STAGING$PREFIX/bin" "$STAGING$PREFIX/lib" "$STAGING$PREFIX/include"
install -m 0755 sqlite3 "$STAGING$PREFIX/bin/sqlite3"
install -m 0644 libsqlite3.a "$STAGING$PREFIX/lib/libsqlite3.a"
install -m 0644 sqlite3.h "$STAGING$PREFIX/include/sqlite3.h"
install -m 0644 sqlite3ext.h "$STAGING$PREFIX/include/sqlite3ext.h"

file "$STAGING$PREFIX/bin/sqlite3"
echo "==> staged in $STAGING (install prefix $PREFIX)"
"$STAGING$PREFIX/bin/sqlite3" --version 2>/dev/null || true
echo "    next: ./sqlite/make-deb.sh"
