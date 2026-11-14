#!/bin/bash
# Build rsync 3.3.0 for armv7 iOS 10.x on Linux.
#
# Why rsync: deployment is the daily pain point (everything moves over scp
# today); rsync gives delta transfer + resumability.  3.3.0 bundles popt,
# zlib and xxhash in-tree, so there are NO external deps to cross-build.
#
# Cross notes:
#   * the git tree ships a pre-generated ./configure (no autoconf needed);
#   * --host=<triplet> switches autoconf into cross mode, where run-probes
#     self-default; feed explicit ac_cv_* only if configure actually chokes;
#   * feature trims for a first build: no openssl/zstd/lz4 (optional
#     checksum/codec plugins -- bundled md5+zlib is plenty), no md2man;
#   * iconv: auto-probed; absent iconv.h in the sysroot just disables it.
#
# Usage: ./build.sh          # output ../out/rsync-<ver>-armv7 (UNSIGNED)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
RSYNC_VERSION="${RSYNC_VERSION:-3.3.0}"
SRC="${RSYNC_SRC:-$HOME/scratch/rsync/rsync-src}"

[ -x "$SRC/configure" ] || { echo "missing $SRC -- git clone --depth 1 --branch v$RSYNC_VERSION https://github.com/WayneD/rsync.git" >&2; exit 1; }

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$SRC"
make distclean >/dev/null 2>&1 || true

# THE dynamic_lookup TRAP (now a standing rule for every configure port):
# cc-wrapper links with -undefined dynamic_lookup, so autoconf's classic
# "declare char fn(); then link" existence probes ALWAYS succeed -- for
# functions the device libSystem does not have (glibc-isms like mallinfo2
# sailed through and then died as `struct mallinfo2` incomplete / dyld
# missing-symbol at launch).  Any ac_cv_func_* that configure "finds" must
# be treated as GUILTY UNTIL the post-link audit passes: force-off known
# glibc-isms here, and the check-undefined.sh gate below catches the rest.
#
# Rationale per override (ALL comments live here, never inside the
# continuation chain below -- a '#' after a line-splice eats the trailing
# backslash and silently disconnects every env var from the configure
# command; this bug cost TWO builds on 2026-11-14, hence the assertions
# after configure):
#   mallinfo/mallinfo2 ......... glibc-isms; device libSystem lacks both.
#   setattrlist/getattrlist/
#   attropen ................... macOS attrlist API; device has the symbols
#                                but the sysroot has no <sys/attr.h> (same
#                                header lsof dropped).  Portable utimes()
#                                fallback; only loss = crtime on synced
#                                files (overlay sys/attr.h would restore).
#   chflags/lchmod ............. Darwin-only; musl stat.h lacks the decls.
#   mknod/linkat ............... sysroot headers lack the decls; rsync
#                                falls back to -1 / plain link().
#   acl_get_file ............... libacl probe; --disable-acl-support too.
#   HAVE_GETTIMEOFDAY_TZ=yes ... a TRUTH override (a "yes", for once): the
#                                hand-made sysroot's sys/time.h is an
#                                11-line minimal header that does not
#                                provide NULL, so the gettimeofday(&tv,
#                                NULL) probe fails on NULL and misreports
#                                the 2-arg signature.  On this platform it
#                                IS 2-arg (sysroot NULL gap -- backlog).
ac_cv_func_mallinfo=no \
ac_cv_func_mallinfo2=no \
ac_cv_func_setattrlist=no \
ac_cv_func_getattrlist=no \
ac_cv_func_attropen=no \
ac_cv_func_chflags=no \
ac_cv_func_lchmod=no \
ac_cv_func_mknod=no \
ac_cv_func_linkat=no \
ac_cv_func_lseek64=no \
ac_cv_func_open64=no \
ac_cv_func_acl_get_file=no \
rsync_cv_HAVE_GETTIMEOFDAY_TZ=yes \
CC="$root/tools/cc-wrapper.sh" \
CFLAGS="-O2" \
./configure \
    --host=armv7-apple-darwin \
    --prefix=/var/mobile/tools/rsync \
    --disable-md2man \
    --disable-openssl \
    --disable-acl-support \
    --disable-xattr-support \
    --disable-iconv \
    --disable-iconv-open \
    --disable-xxhash \
    --disable-zstd \
    --disable-lz4 \
    --disable-debug

# ASSERT the overrides actually landed -- the comment-in-continuation bug
# disconnected them once; these turn any silent regression into a hard stop.
grep -q "^#define HAVE_MALLINFO2" config.h && { echo "FATAL: ac_cv overrides did not reach configure" >&2; exit 1; }
grep -q "^#define HAVE_SETATTRLIST" config.h && { echo "FATAL: setattrlist override did not land" >&2; exit 1; }
grep -q "^#define HAVE_GETTIMEOFDAY_TZ" config.h || { echo "FATAL: GETTIMEOFDAY_TZ truth override did not land" >&2; exit 1; }

make -j"$(nproc)"

BIN="$SRC/rsync"
[ -f "$BIN" ] || { echo "rsync was not built" >&2; exit 1; }

# Post-link audit: every undefined symbol must be provably on the device
# (tbd stubs / libc++).  This is the systematic answer to the probe trap.
"$root/tools/check-undefined.sh" "$BIN"

mkdir -p "$root/out"
cp "$BIN" "$root/out/rsync-$RSYNC_VERSION-armv7"
echo "==> $root/out/rsync-$RSYNC_VERSION-armv7"
file "$root/out/rsync-$RSYNC_VERSION-armv7" | sed 's/^/    /'
echo "    (unsigned by design -- make-deb.sh signs the staged copy;"
echo "     over-ssh use --rsync-path=/var/mobile/tools/bin/rsync on the device,"
echo "     because a non-login shell PATH lacks /var/mobile/tools/bin)"
