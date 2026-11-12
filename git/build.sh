#!/bin/bash
# Build git 2.51.2 for armv7 iOS 10.x on Linux.
#
# Same toolchain family as ../curl and ../wget (see docs/toolchain.md), but
# git does not use autoconf here: its Makefile is driven by a hand-written
# config.mak (below), because configure's probes lie even harder than usual
# on this target and several "uname_S = Linux" defaults leak in when building
# on a Linux host -- the target is iOS, not the build machine.
#
# Static throughout: libz (cross-built in zlib-src), libcurl.a, libssl.a and
# libcrypto.a.  Nothing in /usr is touched; everything installs under
# /var/mobile/tools.
#
# Usage:
#   export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot \
#          IOS_STUBDIR=$HOME/ios-tool \
#          IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
#          LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
#   ./git/build.sh            # builds zlib (if missing) + git, installs to ../tmp/git-staging
#   ./git/make-deb.sh         # packages ../tmp/git-staging into ../out/git_*.deb
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
GIT_VERSION="${GIT_VERSION:-2.51.2}"
SRC="${GIT_SRC:-$HOME/ios-tool/git-src/git-$GIT_VERSION}"
ZLIB="${ZLIB:-$HOME/ios-tool/zlib-src/zlib-1.3.1}"
OSSL="${OSSL:-$HOME/ios-tool/openssl-src/openssl-4.0.3}"
CURL="${CURL:-$HOME/ios-tool/curl-src/curl-8.16.0}"
STAGING="${STAGING:-$root/tmp/git-staging}"
PREFIX="/var/mobile/tools"
CC="$root/tools/cc-wrapper.sh"

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:?set IOS_LD64 to the cctools ld64}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ---------------------------------------------------------------- zlib ----
# git cannot be built without it (there is no --without-zlib).  The rest of
# this repository avoids zlib, so this is the first static libz in the tree.
# Pure C, no syscalls, cross-builds in seconds.
if [ ! -f "$ZLIB/libz.a" ]; then
    [ -d "$ZLIB" ] || {
        mkdir -p "$HOME/ios-tool/zlib-src"
        curl -fL https://zlib.net/zlib-1.3.1.tar.gz -o /tmp/zlib.tar.gz
        tar -C "$HOME/ios-tool/zlib-src" -xzf /tmp/zlib.tar.gz
    }
    ( cd "$ZLIB" \
      && CC="$CC" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
         CHOST=armv7-apple-darwin ./configure --static >/dev/null \
      && make -j"$(nproc)" libz.a >/dev/null )
    # GNU thin archives are silently ignored by ld64 (docs/toolchain.md §2)
    llvm-ar-21 --format=darwin rcs "$ZLIB/libz.a.new" "$ZLIB"/*.o
    # verify the conversion produced real members before replacing anything
    [ "$(llvm-ar-21 t "$ZLIB/libz.a.new" | wc -l)" -gt 0 ] || { echo "libz.a conversion produced 0 members" >&2; exit 1; }
    mv "$ZLIB/libz.a.new" "$ZLIB/libz.a"
fi

# ----------------------------------------------------------------- git ----
if [ ! -d "$SRC" ]; then
    mkdir -p "$HOME/ios-tool/git-src"
    curl -fL "https://github.com/git/git/archive/refs/tags/v$GIT_VERSION.tar.gz" -o /tmp/git.tar.gz
    tar -C "$HOME/ios-tool/git-src" -xzf /tmp/git.tar.gz
fi
[ -f "$CURL/lib/.libs/libcurl.a" ] || { echo "build curl first (curl/build.sh)" >&2; exit 1; }
[ -f "$OSSL/libssl.a" ]           || { echo "build openssl first (openssl/build.sh)" >&2; exit 1; }

cd "$SRC"

# Hand-written cross config.  Notes on every non-obvious line:
cat > config.mak <<MAK
# hand-written cross config for armv7-apple-ios10.3
SHELL_PATH = /bin/sh
CC = $CC
AR = $root/tools/darwin-ar
RANLIB = $root/tools/darwin-ranlib
prefix = $PREFIX
gitexecdir = libexec/git-core
template_dir = share/git-core/templates
sysconfdir = $PREFIX/etc
# nothing here can run scripts: no perl, no python, no tcl on the device
NO_GETTEXT = YesPlease
NO_TCLTK = YesPlease
NO_PERL = YesPlease
NO_PYTHON = YesPlease
NO_EXPAT = YesPlease
NO_ICONV = YesPlease
# git's bundled regex is fine; the sysroot has no usable one to probe
NO_REGEX = YesPlease
# link against our OpenSSL 4, not Apple CommonCrypto
NO_APPLE_COMMON_CRYPTO = YesPlease
OPENSSLDIR = $OSSL
NEEDS_CRYPTO_WITH_SSL = YesPlease
ZLIB_PATH = $ZLIB
CURLDIR = $CURL
CURL_LDFLAGS = -L$CURL/lib/.libs -lcurl
NO_INSTALL_HARDLINKS = YesPlease
HAVE_ALLOCA_H = YesPlease
# git's progress meter uses setitimer; it exists on iOS but probes mislead,
# and the feature is cosmetic -- keep it off
NO_SETITIMER = YesPlease

# ---- overrides for building from a Linux host ----
# config.mak.uname's ifeq(\$(uname_S),Linux) branch assumes the TARGET is
# Linux; it is iOS.  Everything below would otherwise be baked in and either
# fail to compile (sync_file_range, /proc) or abort at first use on the
# device (getrandom).  config.mak is included after config.mak.uname, so
# these ordinary assignments win.
# iOS has no sync_file_range syscall.
HAVE_SYNC_FILE_RANGE =
# iOS has no procfs at all (/proc does not exist).
HAVE_SYSINFO =
HAVE_PLATFORM_PROCINFO =
PROCFS_EXECUTABLE_PATH =
COMPAT_OBJS := \$(filter-out compat/linux/procinfo.o,\$(COMPAT_OBJS))
# iOS libSystem has strlcpy (BSD); do not compile git's compat copy.
NO_STRLCPY =
# iOS libSystem provides arc4random_buf natively; getrandom does not exist
# on iOS 10 and would abort in dyld on first use (symbol not found).
CSPRNG_METHOD = arc4random
# ld64 does not accept -Wl,-rpath,; all libs are static anyway.
CC_LD_DYNPATH = -L
# The cc-wrapper drops -lz from the link line (it assumes libSystem
# re-exports zlib, which is true on macOS but NOT on iOS 10 -- on the
# device deflateInit_ would abort in dyld on first use).  Put the
# converted static archive on the link line explicitly instead.
EXTLIBS += $ZLIB/libz.a
# git's default SHA1 backend is SHA1DC, so the Makefile never adds
# -lssl/-lcrypto (EXTLIBS carries crypto only when OPENSSL_SHA1 is
# selected) -- but curl's TLS needs them.  Append the static archives to
# EXTLIBS (used late, in the link recipes; CURL_LIBCURL is NOT usable --
# its plain assignments at Makefile:1663/1666 run after config.mak and
# would silently overwrite anything appended here).
EXTLIBS += $OSSL/lib/libssl.a $OSSL/lib/libcrypto.a
MAK

make -j"$(nproc)" git git-remote-http >/dev/null

# ----------------------------------------------------------- install ------
# Plain `make install` drags in three things we do not ship (each found the
# hard way):
#   * imap-send: pokes opaque OpenSSL 4 ASN1 structs, does not compile, and
#     is useless on the device.  NO_IMAP_SEND in config.mak does NOT work --
#     the `ifndef NO_IMAP_SEND` at Makefile:773 is evaluated *before*
#     config.mak is included, so it must be given on the command line.
#   * oss-fuzz targets: LINK_FUZZ_PROGRAMS = YesPlease leaks from the Linux
#     branch of config.mak.uname and the fuzz link line uses GNU-ld-only
#     options (--allow-multiple-definition) that ld64 rejects.
#   * test programs: Makefile:3262 appends $(TEST_PROGRAMS), $(UNIT_TEST_PROGS)
#     and $(CLAR_TEST_PROG) to `all::` UNCONDITIONALLY.  Blank them on the
#     command line; command-line variables override everything.
rm -rf "$STAGING" && mkdir -p "$STAGING"
make install DESTDIR="$STAGING" \
    NO_IMAP_SEND=YesPlease LINK_FUZZ_PROGRAMS= \
    TEST_PROGRAMS= UNIT_TEST_PROGS= CLAR_TEST_PROG= test_bindir_programs= \
    -j"$(nproc)" >/dev/null

# git-cvsserver is a perl script; NO_PERL keeps most perl bits out but this
# one still lands in bin/ (its shebang is the tell).
rm -f "$STAGING$PREFIX/bin/git-cvsserver"
# sample hooks: watchman's needs perl, and .sample hooks are inert anyway
rm -f "$STAGING$PREFIX/share/git-core/templates/hooks/"*.sample

echo "==> staged in $STAGING (install prefix $PREFIX)"
echo "    next: ./git/make-deb.sh"
