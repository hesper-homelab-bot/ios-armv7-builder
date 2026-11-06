#!/bin/bash
# Build Dropbear (verified with 2026.94) for armv7 iOS 10.x on Linux.
#
# Dropbear is a far better fit for this device than OpenSSH 10.x, and the
# reason is worth recording because it decides the whole port:
#
#   * it bundles libtomcrypt + libtommath, so there is no OpenSSL to
#     cross-compile -- which removes the single hard blocker OpenSSH has,
#     because OpenSSH's configure *executes* the openssl binary to probe its
#     version and an armv7 binary cannot run on the Linux host;
#   * --disable-zlib removes the zlib dependency entirely, and neither the
#     sysroot nor the device has zlib.h;
#   * its autoconf surface is much smaller than OpenSSH's (and it has no
#     vendored gnulib to fight, unlike wget).
#
# Everything else is the usual sysroot work.  See ../README.md for the ABI
# story and ios-config.site in this directory for why the probes lie, plus
# sysroot-overlay/ for the missing declarations.
#
# Usage:
#   LD64=.../x86_64-apple-darwin13.4.0-ld LD64_LIBS=... \
#       [WGET_SRC=/path/to/dropbear-2026.94] ./build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
DB_VERSION="${DB_VERSION:-2026.94}"
SRC="${DB_SRC:-$HOME/ios-tool/dropbear-src/dropbear-$DB_VERSION}"
PREFIX="${PREFIX:-/var/mobile/tools}"

[ -d "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "run tmux/build.sh first" >&2; exit 1; }

# libSystem.tbd lives next to the toolchain in ~/ios-tool, not in this repo
# (the repo is public; the Apple-built stub is not redistributed).
export IOS_LD64="${IOS_LD64:-${LD64:-}}" IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set LD64 to the cctools ld64" >&2; exit 1; }
export LD_LIBRARY_PATH="${LD64_LIBS:-}:${LD_LIBRARY_PATH:-}"

# configure's link tests always "succeed" here because the wrapper links with
# -undefined dynamic_lookup, so they accept calls to functions iOS has never
# had.  ios-config.site corrects them.  It must be a config.site rather than
# --cache-file: autoconf rewrites the cache at the end of every run, so
# hand-edited cache values survive exactly one configure.
export CONFIG_SITE="$here/ios-config.site"

cd "$SRC"
make distclean >/dev/null 2>&1 || true

# Dropbear's sysoptions.h enforces a compile-time invariant:
#
#     #if DROPBEAR_SVR_DROP_PRIVS && !defined(HAVE_SETRESGID)
#     #  error "DROPBEAR_SVR_DROP_PRIVS requires setresgid()."
#
# and DROPBEAR_SVR_DROP_PRIVS means "change the server process to user
# privileges after authentication" -- turning it off would run every session
# as root, which is a real security regression and is not on the table.
#
# iOS 10 exports neither setresgid nor setresuid (verified on the device:
# calling either aborts with "dyld: Symbol not found: _setresgid").  So the
# honest situation is:
#
#   * the actual privilege drop uses setgid(), initgroups() and setuid(),
#     which iOS does have;
#   * setresgid appears exactly once in the whole tree (svr-auth.c:519), to
#     retain the utmp group so wtmp records can be written.  That call site
#     already checks its return value and only sets have_utmp_gid on success,
#     so returning failure takes a path Dropbear is built to handle -- and
#     utmp is disabled below anyway.
#
# The response is a static inline shim in sysroot-overlay/usr/include/unistd.h
# which returns -1 for the "saved id only" request Dropbear actually makes,
# plus these two defines so the invariant holds and the real drop keeps
# working.  static inline keeps the shim out of the object archive, so
# configure's own link test still reports "no" -- the truth.
# Dropbear 2026.94 turns off RSA-with-SHA-1 host key signatures by default
# (default_options.h: "#define DROPBEAR_RSA_SHA1 0"), because SHA-1 is weak.
# The device's existing sshd is OpenSSH 6.7p1, which offers *only* the
# ssh-rsa (SHA-1) host key algorithm -- RSA-SHA2 arrived in OpenSSH 7.2 -- so
# dbclient against it dies with
#     "Connection to mobile@localhost:22 exited: No matching algo hostkey"
#
# Turning DROPBEAR_RSA_SHA1 back on restores interop.  This is parity, not a
# regression: the 6.7p1 sshd we are talking to already does nothing but SHA-1,
# and a peer that supports rsa-sha2 still prefers it, so modern connections
# are unaffected and only the legacy host key path is re-enabled.
# The bundled scp client is a thin front end that execs dbclient from a
# hardcoded path: default_options.h has
#     #define DROPBEAR_PATH_SSH_PROGRAM "/usr/bin/dbclient"
# so out of the box db-scp dies with "/usr/bin/dbclient: No such file or
# directory" -- which is how it failed on the device first time.  Pointing it
# at the path this kit actually installs avoids putting anything in /usr.
EXTRA_CFLAGS="-DHAVE_SETRESGID=1 -DHAVE_SETRESUID=1 -DDROPBEAR_RSA_SHA1=1"

# The bundled scp client execs dbclient from a hardcoded path in
# default_options.h:
#     #define DROPBEAR_PATH_SSH_PROGRAM "/usr/bin/dbclient"
# so out of the box db-scp dies with "/usr/bin/dbclient: No such file or
# directory" -- exactly how it failed on the device.  Pointing it at the path
# this kit installs avoids putting anything in /usr.
#
# It has to be rewritten in the header rather than passed with -D: the value
# is a string literal, and every layer between here and the compiler
# (configure -> Makefile -> $(CC) $(CFLAGS) -> /bin/sh) strips quotes from a
# -D argument, which leaves the macro expanding to bare tokens and scp.c
# failing with "expected expression".
SCP_PATH_DEFAULT='/usr/bin/dbclient'
SCP_PATH_WANTED='"/var/mobile/tools/db-dbclient"'

# zlib is optional (only stream compression) and we have no headers for it.
# utmp/utmpx/wtmp are for login accounting, which iOS does not really do;
# --disable-loginfunc also keeps Dropbear from using musl's struct utmp
# layout, which is a *utmpx* alias and is not Darwin's at all.
# shadow password support needs <shadow.h>, which iOS has no use for.
CC="$root/tools/cc-wrapper.sh" AR="$root/tools/darwin-ar" \
RANLIB="$root/tools/darwin-ranlib" \
CFLAGS="$EXTRA_CFLAGS" \
./configure --host=armv7-apple-darwin --prefix="$PREFIX" \
    --disable-zlib \
    --disable-lastlog --disable-shadow \
    --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx \
    --disable-loginfunc \
    >/dev/null

# Rewrite the scp client's hardcoded dbclient path now that the build tree is
# in its configured state.  This is a downloaded tarball rather than a repo,
# so the tree is regarded as disposable and in-place edits are fine.
sed -i "s|^#define DROPBEAR_PATH_SSH_PROGRAM .*|\
#define DROPBEAR_PATH_SSH_PROGRAM $SCP_PATH_WANTED|" src/default_options.h
grep -q 'DROPBEAR_PATH_SSH_PROGRAM' src/default_options.h || {
    echo "scp dbclient path was not rewritten" >&2; exit 1; }

# Programs to build.  scp is bundled, and SCPPROGRESS gives the progress bar.
#
# No sftp-server by default, and that is a property of Dropbear itself rather
# than a choice we made: it ships no sftp server at all.  The only thing it
# has is a *path* it execs when a client asks for the "sftp" subsystem --
# SFTPSERVER_PATH below, defaulting to /usr/libexec/sftp-server, which on this
# device belongs to the openssh dpkg package.  Leaving that default alone is
# what ties dropbear's sftp to openssh staying installed.  scp is unaffected:
# db-scp execs a path of our own (see the DROPBEAR_PATH_SSH_PROGRAM rewrite
# above), which is why it survives openssh being removed.
#
# WITH_DB_SFTPSERVER=1 opts in to the from-scratch SFTP server in
# ../sftp-server/: it is compiled, SFTPSERVER_PATH is repointed at
# $PREFIX/db-sftp-server, and make-deb.sh ships it.  Off by default.  Note that
# this is a hand-written network file-access subsystem -- it is NOT audited,
# and it is not on by default precisely so that it is not exposed by accident.
PROGRAMS="dropbear dbclient dropbearkey scp"
if [ "${WITH_DB_SFTPSERVER:-0}" = "1" ]; then
    SFTP_PATH="$PREFIX/db-sftp-server"
    "$root/tools/cc-wrapper.sh" "$root/sftp-server/sftp-server.c" -o sftp-server \
        || { echo "sftp-server did not build" >&2; exit 1; }
    PROGRAMS="$PROGRAMS sftp-server"
else
    # Restored explicitly rather than left alone.  The source tree is reused
    # across builds (DB_SRC points at a persistent directory, not a freshly
    # extracted tarball), so an in-place sed made by a previous WITH_DB_SFTPSERVER=1
    # run would otherwise survive into this default build and silently ship a
    # dropbear that execs a file this package does not install.
    SFTP_PATH="/usr/libexec/sftp-server"
fi
sed -i "s|^#define SFTPSERVER_PATH .*|#define SFTPSERVER_PATH \"$SFTP_PATH\"|" \
    src/default_options.h
grep -q "$SFTP_PATH" src/default_options.h || {
    echo "SFTPSERVER_PATH was not rewritten to $SFTP_PATH" >&2; exit 1; }

# shellcheck disable=SC2086
make -j"$(nproc)" PROGRAMS="$PROGRAMS" SCPPROGRESS=1 >/dev/null

ldid -S dropbear dbclient dropbearkey 2>/dev/null || true
mkdir -p "$root/out"
for p in $PROGRAMS; do
    [ -f "$p" ] || { echo "$p was not built" >&2; exit 1; }
    cp "$p" "$root/out/dropbear-$p-$DB_VERSION-armv7"
done
echo "==> $root/out/dropbear-{$PROGRAMS}-$DB_VERSION-armv7"
[ "${WITH_DB_SFTPSERVER:-0}" = "1" ] && \
    echo "    WITH_DB_SFTPSERVER=1: sftp served by db-sftp-server (unaudited)"
echo "    server runs on its own port; do NOT replace /usr/sbin/sshd"
echo "    (SSH is the only remote access to this device)"
