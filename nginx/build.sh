#!/bin/bash
# Build nginx 1.26.3 (stable) for armv7 iOS 10.x on a Linux host.
#
# nginx's configure is a hand-written /bin/sh script, not autoconf.  It picks
# the *target* OS from `uname -s` of the build machine, so on Linux it would
# take the Linux branch (epoll, Linux sendfile(2), eventfd, SO_REUSEPORT...)
# and produce a binary that cannot work on iOS.  We do not patch auto/os/conf;
# we tell configure the truth instead:
#
#     --crossbuild=Darwin:16.7.0:armv7
#
# sets NGX_PLATFORM so auto/os/conf sources auto/os/darwin.  That yields
# NGX_HAVE_KQUEUE + NGX_HAVE_CLEAR_EVENT + the kqueue event module and the
# Darwin sendfile chain -- kqueue being the engine the iOS kernel genuinely
# provides (nmap/nsock fell back to it after HAVE_EPOLL was #undef'd; see
# nmap/build.sh wall #7).
#
# Wall list -- every entry cost real time:
#
#  1. cc-wrapper links with -undefined dynamic_lookup, so a *compile+link*
#     feature probe always succeeds, and a *run* probe (ngx_feature_run=yes)
#     can never execute: the probe binary is armv7 Mach-O and the build host
#     is x86 Linux.  nginx reports "found but is not working" and leaves the
#     NGX_HAVE_* macro *out* of objs/ngx_auto_config.h -- a silent false
#     NEGATIVE, e.g. for the Darwin sendfile() and EVFILT_TIMER probes.
#     Do not try to make the probes honest; patch objs/ngx_auto_config.h
#     *after* configure (see the macro block below), which is exactly what
#     the task calls for.  Same failure class as docs/toolchain.md §8.
#
#  2. --with-pcre=DIR and --with-zlib=DIR are the *clean* way to pull in the
#     prebuilt static archives: auto/lib/pcre/conf detects PCRE2 by the
#     presence of $PCRE/src/pcre2.h.generic and then puts
#     $PCRE/.libs/libpcre2-8.a straight into CORE_LIBS; auto/lib/zlib/conf
#     puts $ZLIB/libz.a into CORE_LIBS.  No -l flag, no -L, no sed of the
#     generated Makefile.  The pcre2 archive must already be a *Darwin flat*
#     archive -- ld64 silently ignores GNU thin archives
#     (docs/toolchain.md §2); nmap's port leaves one in the right format,
#     so we verify its member count rather than trusting it.
#
#  3. --with-openssl=DIR must NOT be used: nginx expects a *source tree* it
#     will configure and build itself, under $OPENSSL/.openssl/.  Our OpenSSL
#     4.0.3 is already cross-built (libssl.a/libcrypto.a at the top, headers
#     in include/).  Leaving --with-openssl off sends nginx down its
#     auto-detection branch, which probes `-lssl -lcrypto`; under the
#     wrapper's -undefined dynamic_lookup that probe "succeeds", sets
#     NGX_SSL/NGX_OPENSSL, and only the include path is missing.  We supply
#     it with --with-cc-opt -I$OSSL/include and make sure the archives are
#     on the link line (see 4).  --with-http_ssl_module is what actually
#     turns NGX_HTTP_SSL on.
#
#  4. The cc-wrapper drops a fixed list of -l* arguments that are "inside
#     libSystem" on macOS -- -lz among them -- but that re-export is NOT
#     true on iOS 10, and it cannot resolve -lpcre2-8 without a -L anyway.
#     git/build.sh hit exactly this with libz.a.  Even though CORE_LIBS now
#     carries the pcre2/zlib paths from wall #2, the OpenSSL archives are
#     only referenced as -lssl -lcrypto; we add both as explicit paths (and
#     a -L for good measure) through --with-ld-opt so the link line is
#     self-sufficient.  Static archives are also order-sensitive for ld64
#     in the sense that a member is only pulled when a symbol is still
#     undefined, so they go last.
#
#  5. iOS has no /var/run and no /usr/local.  Everything -- binaries, conf,
#     logs, temp paths, html -- lives under /var/mobile/tools/nginx so the
#     package is self-contained and removable with one rm -rf, matching
#     every other package in this repo.  All the *_temp_path and *_path
#     options are spelled out because nginx's defaults point at /var/run.
#
#  6. nginx 1.26 wants `struct sockaddr`/`ngx_atomic` etc. from the sysroot;
#     nothing extra was needed beyond what the sysroot already carries (no
#     new headers, no new overlays).  -Wno-error guards any warning that
#     clang elevates on this target.
#
# Usage:
#   export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot \
#          IOS_STUBDIR=$HOME/ios-tool \
#          IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
#          LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
#   ./nginx/build.sh          # -> ../out/nginx-<ver>-armv7 + ../tmp/nginx-staging
#   ./nginx/make-deb.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
NGINX_VERSION="${NGINX_VERSION:-1.26.3}"
SRC="${NGINX_SRC:-$HOME/ios-tool/nginx-src/nginx-$NGINX_VERSION}"
PCRE_DIR="${PCRE_DIR:-$HOME/ios-tool/nginx-src/pcre2-ios}"
PCRE_A="$PCRE_DIR/.libs/libpcre2-8.a"
ZLIB="${ZLIB:-$HOME/ios-tool/zlib-src/zlib-1.3.1}"
OSSL="${OSSL:-$HOME/ios-tool/openssl-src/openssl-4.0.3}"
PREFIX="${PREFIX:-/var/mobile/tools/nginx}"
STAGING="${STAGING:-$root/tmp/nginx-staging}"
JOBS="${JOBS:-$(nproc)}"
CC="$root/tools/cc-wrapper.sh"

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:?set IOS_LD64 to the cctools ld64}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ------------------------------------------------------------ sources ----
if [ ! -d "$SRC" ]; then
    mkdir -p "$HOME/ios-tool/nginx-src"
    curl -fL --http1.1 "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" \
        -o "/tmp/nginx-$NGINX_VERSION.tar.gz"
    tar -C "$HOME/ios-tool/nginx-src" -xzf "/tmp/nginx-$NGINX_VERSION.tar.gz"
fi

# ------------------------------------------------------------- pcre2 -----
# nginx needs a PCRE2 static archive.  It is built here, in a *private*
# source tree under $HOME/ios-tool/nginx-src/pcre2-ios, on purpose.
#
# Do NOT point nginx at nmap's shared libpcre tree: --with-pcre=DIR (or any
# PCRE=<path> spelling) makes nginx run the upstream configure *and* `make
# distclean` in that directory.  The distclean deletes .libs/libpcre2-8.a and
# every object, which silently breaks a future nmap rebuild.  That happened
# once during this port; the private tree is the fix.  (nmap's own *binary*
# was already built and is unaffected.)
#
# The private tree is created by extracting just libpcre from nmap's cached
# tarball, so no extra download is needed.  The recipe mirrors
# nmap/build.sh: --disable-shared --enable-static, then the GNU archive is
# re-packed as a Darwin flat archive because ld64 silently ignores GNU thin
# archives (docs/toolchain.md §2).  Member count is verified -- a conversion
# that "succeeds" with 0 members is a known failure mode.
if [ ! -f "$PCRE_A" ]; then
    echo "==> building private pcre2 static archive"
    NMA_TB="$HOME/ios-tool/nmap-src/nmap.tar.bz2"
    [ -f "$NMA_TB" ] || { echo "missing $NMA_TB (needed to seed pcre2 sources)" >&2; exit 1; }
    rm -rf "$PCRE_DIR"
    mkdir -p "$PCRE_DIR"
    tar -C /tmp -xjf "$NMA_TB" "nmap-*/libpcre" 2>/dev/null || true
    pcre_seed="$(ls -d /tmp/nmap-*/libpcre 2>/dev/null | head -1)"
    [ -n "$pcre_seed" ] || { echo "could not extract libpcre from $NMA_TB" >&2; exit 1; }
    cp -a "$pcre_seed/." "$PCRE_DIR/"
    # The copied tree keeps 2024 mtimes on configure/aclocal.m4/Makefile.in;
    # make then decides they are stale and reruns aclocal, which fails in a
    # tree without the full autotools state.  Touching them after the tarball
    # copy keeps make from regenerating what already exists.
    ( cd "$PCRE_DIR" \
      && CC="$CC" CXX="$HOME/ios-tool/cxx-wrapper.sh" \
         AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
         ./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools \
                     --disable-shared --enable-static >/dev/null \
      && touch aclocal.m4 configure Makefile.in src/config.h.in m4/*.m4 \
      && sleep 1 && touch aclocal.m4 configure Makefile.in src/config.h.in \
      && make -j"$JOBS" >/dev/null )
    ( cd "$PCRE_DIR/src" \
      && llvm-ar-21 --format=darwin rcs "$PCRE_DIR/.libs/libpcre2-8.a.new" \
             libpcre2_8_la-*.o \
      && [ "$(llvm-ar-21 t "$PCRE_DIR/.libs/libpcre2-8.a.new" | wc -l)" -gt 0 ] \
      && mv "$PCRE_DIR/.libs/libpcre2-8.a.new" "$PCRE_DIR/.libs/libpcre2-8.a" )
fi

# ------------------------------------------------------- dependencies ----
[ -f "$PCRE_A" ]       || { echo "missing $PCRE_A (see the pcre2 block below)" >&2; exit 1; }
[ -f "$ZLIB/libz.a" ]  || { echo "missing $ZLIB/libz.a" >&2; exit 1; }
[ -f "$OSSL/libssl.a" ]    || { echo "missing $OSSL/libssl.a" >&2; exit 1; }
[ -f "$OSSL/libcrypto.a" ] || { echo "missing $OSSL/libcrypto.a" >&2; exit 1; }

# A GNU thin archive here is silently ignored by ld64 and only surfaces as
# undefined _pcre2_compile_8 at the very end of the build.  Verify up front.
mems=$(llvm-ar-21 t "$PCRE_A" 2>/dev/null | wc -l)
[ "$mems" -gt 0 ] || { echo "$PCRE_A has 0 members (not a usable archive)" >&2; exit 1; }
echo "==> pcre2 archive: $mems members (Darwin flat)"

# ------------------------------------------------- configure patches ----
# See nginx/patch-nginx.py for the reasoning; the patches route nginx's
# *run* probes through nginx/crossanswer.sh and supply the armv7 ABI type
# sizes from a _Static_assert-verified table instead of executing a Mach-O
# binary on a Linux host.  Idempotent, so a re-run is always safe.
cd "$SRC"
python3 "$here/patch-nginx.py" "$SRC" "$here/crossanswer.sh"
rm -rf objs

# nginx finds PCRE2 either by a bare -lpcre2-8 link probe (impossible when
# cross-compiling) or, failing that, through `pcre2-config`.  A fake
# pcre2-config on PATH is the supported hook that hands nginx our private
# static archive; see nginx/pcre2-config.
export PATH="$here:$PATH"
export NGX_PCRE2_DIR="$PCRE_DIR"

CC_OPT="-O2 -I$PCRE_DIR/src -I$ZLIB -I$OSSL/include -Wno-error"
# explicit archives, last on the link line (wall #4)
LD_OPT="$PCRE_A $ZLIB/libz.a $OSSL/libssl.a $OSSL/libcrypto.a -L$OSSL"

sh ./configure \
    --crossbuild=Darwin:16.7.0:armv7 \
    --prefix="$PREFIX" \
    --conf-path="$PREFIX/conf/nginx.conf" \
    --error-log-path="$PREFIX/logs/error.log" \
    --http-log-path="$PREFIX/logs/access.log" \
    --pid-path="$PREFIX/logs/nginx.pid" \
    --lock-path="$PREFIX/logs/nginx.lock" \
    --http-client-body-temp-path="$PREFIX/tmp/client_body" \
    --http-proxy-temp-path="$PREFIX/tmp/proxy" \
    --http-fastcgi-temp-path="$PREFIX/tmp/fastcgi" \
    --http-uwsgi-temp-path="$PREFIX/tmp/uwsgi" \
    --http-scgi-temp-path="$PREFIX/tmp/scgi" \
    --with-cc="$CC" \
    --with-cc-opt="$CC_OPT" \
    --with-ld-opt="$LD_OPT" \
    --with-pcre \
    --with-pcre-opt="-I$PCRE_DIR/src" \
    --with-zlib-opt="-I$ZLIB" \
    --with-http_ssl_module \
    --with-threads \
    --without-http_uwsgi_module \
    --without-http_scgi_module \
    --without-http_fastcgi_module \
    --without-http_grpc_module \
    --without-http_memcached_module \
    --without-http_auth_basic_module \
    --without-mail_pop3_module \
    --without-mail_imap_module \
    --without-mail_smtp_module \
    --without-http_upstream_zone_module

# ------------------------------------------- platform macro correction ----
# Wall #1: the run-probes could not execute, so their macros are missing.
# set_macro rewrites an existing #define or appends one; unset_macro comments
# a false positive out.  Both are idempotent.
CONF_H=objs/ngx_auto_config.h

set_macro() { # NAME VALUE
    local n="$1" v="$2"
    if grep -qE "^#define[[:space:]]+$n([[:space:]]|$)" "$CONF_H"; then
        sed -i -E "s|^#define[[:space:]]+$n([[:space:]].*)?\$|#define $n $v|" "$CONF_H"
    elif grep -qE "^/\* #undef $n" "$CONF_H"; then
        sed -i -E "s|^/\* #undef $n.*\$|#define $n $v|" "$CONF_H"
    else
        printf '#ifndef %s\n#define %s %s\n#endif\n' "$n" "$n" "$v" >> "$CONF_H"
    fi
}
unset_macro() { # NAME
    grep -qE "^#define[[:space:]]+$1([[:space:]]|$)" "$CONF_H" \
        && sed -i -E "s|^#define[[:space:]]+$1([[:space:]].*)?\$|/* #undef $1 -- absent on iOS */|" "$CONF_H"
    return 0
}

echo "==> correcting platform macros in $CONF_H"

# --- event engine: kqueue is the real one on iOS (device-verified) --------
set_macro NGX_HAVE_KQUEUE 1
set_macro NGX_HAVE_CLEAR_EVENT 1
set_macro NGX_HAVE_TIMER_EVENT 1     # EVFILT_TIMER works on iOS 10 (nmap probe)
set_macro NGX_HAVE_KQUEUE_EVENT 1

# --- Linux-only primitives: the iOS kernel has no such syscalls -----------
unset_macro NGX_HAVE_EPOLL
unset_macro NGX_HAVE_EPOLLRDHUP
unset_macro NGX_HAVE_EPOLLEXCLUSIVE
unset_macro NGX_HAVE_EPOLLET
unset_macro NGX_HAVE_EVENTFD
unset_macro NGX_HAVE_SYS_EVENTFD_H
unset_macro NGX_HAVE_FILE_AIO
unset_macro NGX_HAVE_SENDFILE64
unset_macro NGX_HAVE_SENDFILEV
unset_macro NGX_HAVE_SENDFILEV64
unset_macro NGX_HAVE_READ_AHEAD
unset_macro NGX_HAVE_F_READAHEAD
unset_macro NGX_HAVE_ACCEPT4
unset_macro NGX_HAVE_GETRANDOM
unset_macro NGX_HAVE_SCHED_SETAFFINITY
unset_macro NGX_HAVE_CPUSET_SETAFFINITY
unset_macro NGX_HAVE_SET_AFFINITY
unset_macro NGX_HAVE_POSIX_FADVISE
unset_macro NGX_HAVE_SO_REUSEPORT
unset_macro NGX_LINUX
unset_macro NGX_HAVE_TAINTED_NONE

# --- sendfile: deliberately OFF (wall #2).  The Darwin branch still compiles
#     ngx_darwin_sendfile_chain.c, but without NGX_HAVE_SENDFILE nginx serves
#     through the portable read/write chain.  Slower, provably correct; a
#     wrong sendfile assumption shows up as truncated responses, which is far
#     more expensive to debug than the small throughput loss.
unset_macro NGX_HAVE_SENDFILE

# --- poll(2): present on iOS and used outside the event loop --------------
set_macro NGX_HAVE_POLL 1
set_macro NGX_HAVE_POLL_H 1

# --- Darwin/BSD facts the run-probes could not establish ------------------
set_macro NGX_DARWIN 1
set_macro NGX_HAVE_DARWIN 1
set_macro NGX_HAVE_GETADDRINFO 1
set_macro NGX_HAVE_UNIX_DOMAIN 1
set_macro NGX_HAVE_DEFERRED_ACCEPT 1

echo "==> final platform macros:"
grep -E "NGX_HAVE_(KQUEUE|CLEAR_EVENT|EPOLL|SENDFILE|POLL|TIMER_EVENT|EVENTFD)[[:space:]]|NGX_LINUX|NGX_DARWIN[[:space:]]" "$CONF_H" | sed 's/^/    /'

# -------------------------------------------------------------- build ----
make -j"$JOBS"

ls -la objs/nginx
file objs/nginx || true

mkdir -p "$root/out"
cp objs/nginx "$root/out/nginx-$NGINX_VERSION-armv7"
ldid -S "$root/out/nginx-$NGINX_VERSION-armv7" 2>/dev/null || true
echo "==> $root/out/nginx-$NGINX_VERSION-armv7"
echo "    next: ./nginx/make-deb.sh"
