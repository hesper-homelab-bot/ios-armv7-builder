#!/bin/bash
# Build nmap 7.95 (nmap + ncat, no nping) for armv7 iOS 10.x on Linux.
#
# By far the most invasive port in this repository.  nmap builds FIVE
# bundled libraries (pcre2, lua, libdnet, liblinear, nsock/nbase/libnetutil
# trees) plus its own C++ core, and every one of them tripped over either
# the Linux-host defaults or a sysroot gap that earlier packages never
# touched.  The full wall list:
#
#  1. bundled libpcre2 has no pre-generated configure -> host autoreconf -fi
#     first; and its libtool link wants a -soname dylib, which ld64 has no
#     use for here -> configure libpcre with --disable-shared.
#  2. liblua.a, liblinear.a, libnsock.a, libnbase.a, libnetutil.a are
#     created by plain GNU ar and are silently ignored by ld64
#     (docs/toolchain.md §2) -> every archive is re-packed with
#     llvm-ar-21 --format=darwin after the build.
#  3. libdnet-stripped picks its backends from configure probes that lie
#     under -undefined dynamic_lookup:
#       route: linux_procfs probe falsely succeeds -> pin
#         ac_cv_dnet_route_h_has_rt_msghdr=yes / ac_cv_dnet_linux_procfs=no
#         so route-bsd.c is used (the device's real backend).
#       arp:   arp-ioctl.c (Linux) is hardcoded in the stripped Makefile
#         -> sed it to arp-bsd.c, the Darwin one.
#       intf:  intf.c needs SIOCGIFCONF etc from <sys/sockio.h>; the probe
#         ran before this repo carried that header -> #define
#         HAVE_SYS_SOCKIO_H 1 in include/config.h after the fact.
#  4. The sysroot itself had Linux-flavoured holes, fixed for good in
#     sysroot-overlay/ (see the header comments there):
#       * sys/ioctl.h shipped the LINUX SIOCGIFCONF (0x8912) block; removed,
#         XNU's bsd/sys/sockio.h now provides the real BSD values.
#       * net/route.h had no rt_msghdr (musl) -> XNU bsd/net/route.h.
#       * assert.h called __assert_fail (musl) which libSystem does not
#         export -> __assert_rtn (probe-verified live).
#       * netdb.h shipped glibc NI_/AI_/EAI_ values; Darwin's differ
#         (NI_NUMERICHOST is 2 here, not 1!) -> Libinfo values.
#       * netinet/in.h lacked IPPROTO_ICMPV6 etc -> XNU values appended.
#       * netinet/in6.h gained the RFC 3542 IPV6_* option constants.
#       * net/if.h gained struct ifaliasreq (sockio.h's SIOCAIFADDR does
#         sizeof it).
#       * sys/un.h gained SUN_LEN.
#       * unistd.h/getopt.h getopt_long* declarations made const-compatible
#         with nbase/getopt.h (char ** not char *const []).
#  5. nsock's makefile.dep rule runs `$(CC) -MM` -- which the cc-wrapper
#     treated as an unknown flag and forwarded to a full compile+link, so
#     clang wrote the DEPENDENCY LIST into every scanned .o (ASCII poison).
#     The wrapper now passes -M/-MM/-MD/-MMD through untouched; this script
#     also deletes any object still poisoned from earlier attempts.
#  6. OpenSSL 4 made ASN1 opaque and X509 accessors const -- nmap 7.95 and
#     ncat still poke fields directly.  Patches applied below (idempotent).
#  7. nsock's engine table picked up epoll from a musl sys/epoll.h probe
#     (the header exists, the syscall does not) -> HAVE_EPOLL is #undef'd in
#     nsock/include/nsock_config.h; nsock falls back to kqueue, which the
#     iOS kernel genuinely provides.
#  8b. musl's sys/socket.h also #define'd SO_BINDTODEVICE (25) -- a Linux
#     only sockopt the iOS kernel answers with EAFNOSUPPORT.  nbase's
#     socket_bindtodevice() is #ifdef-guarded on that macro, so every scan
#     logged "Setting of SO_BINDTODEVICE failed ... (42)" twice.  The macro
#     is now removed from the sysroot header (Darwin does source-interface
#     selection with IP_BOUND_IF instead) and the warning is gone.
#  8. The deepest one: musl's bits/ioctl.h defined _IO/_IOR/_IOW/_IOWR with
#     LINUX semantics, so every BSD header that builds ioctl numbers with
#     those macros (net/bpf.h's BIOCSETIF, sockio.h's SIOCAIFADDR, ...)
#     silently got garbage request codes -- and the value changed depending
#     on which header was included first.  bits/ioctl.h now includes
#     <sys/ioccom.h> (BSD macros) and carries the Darwin tty numbers
#     unconditionally.  Same class as wall #4 but one level deeper.
#
# Usage:
#   export IOS_SYSROOT=$HOME/ios-tmux-builder/tmp/sysroot \
#          IOS_STUBDIR=$HOME/ios-tool \
#          IOS_LD64=$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
#          LD_LIBRARY_PATH=$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib
#   ./nmap/build.sh          # -> ../out/nmap-7.95-armv7 (+ data files)
#   ./nmap/make-deb.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
NMAP_VERSION="${NMAP_VERSION:-7.95}"
SRC="${NMAP_SRC:-$HOME/ios-tool/nmap-src/nmap-$NMAP_VERSION}"
PCAP_INST="${PCAP_INST:-$HOME/ios-tool/libpcap-installed/var/mobile/tools}"
OSSL="${OSSL:-$HOME/ios-tool/openssl-src/openssl-4.0.3}"
ZLIB="${ZLIB:-$HOME/ios-tool/zlib-src/zlib-1.3.1}"
CC="$root/tools/cc-wrapper.sh"
CXXW="$HOME/ios-tool/cxx-wrapper.sh"

export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
export IOS_LD64="${IOS_LD64:?set IOS_LD64 to the cctools ld64}"
export LD_LIBRARY_PATH="$HOME/ios-tool/x-libdispatch/lib:$HOME/ios-tool/x-tapi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

[ -f "$PCAP_INST/lib/libpcap.a" ] || { echo "run libpcap/build.sh first" >&2; exit 1; }
[ -f "$OSSL/libssl.a" ]           || { echo "build openssl first" >&2; exit 1; }
[ -f "$ZLIB/libz.a" ]             || { echo "build zlib first (git/build.sh does)" >&2; exit 1; }

# ------------------------------------------------------------- source ----
[ -d "$SRC" ] || {
    mkdir -p "$HOME/ios-tool/nmap-src"
    curl -fsSL --http1.1 https://nmap.org/dist/nmap-$NMAP_VERSION.tar.bz2 -o /tmp/nmap.tar.bz2
    tar -C "$HOME/ios-tool/nmap-src" -xjf /tmp/nmap.tar.bz2
}
cd "$SRC"

# pre-generate the bundled pcre2 configure (needs host autotools)
[ -x libpcre/configure ] || { ( cd libpcre && autoreconf -fi >/dev/null 2>&1 ); }

# --------------------------------------------------- OpenSSL 4 patches ----
# nse_ssl_cert.cc / ncat/ncat_ssl.c / nsock/src/nsock_ssl.c poke opaque
# ASN1 structs and use OPENSSL_atexit (removed in OpenSSL 4).  Idempotent.
python3 - <<'PY'
import re
def patch(path, pairs):
    s = open(path).read()
    for old, new in pairs:
        if new in s: continue
        assert old in s, (path, old)
        s = s.replace(old, new, 1)
    open(path, 'w').write(s)

patch('nse_ssl_cert.cc', [
 ('    entry = X509_NAME_get_entry(name, i);',
  '    /* OpenSSL 3+/4 returns const X509_NAME_ENTRY *; read-only use. */\n    entry = (X509_NAME_ENTRY *) X509_NAME_get_entry(name, i);'),
 ('    lua_pushlstring(L, (const char *) value->data, value->length);',
  '    /* OpenSSL 3+/4 made ASN1_STRING opaque: use the accessors. */\n    lua_pushlstring(L, (const char *) ASN1_STRING_get0_data(value),\n                    ASN1_STRING_length(value));'),
 ('    obj = X509_EXTENSION_get_object(ext);',
  '    /* OpenSSL 3+/4: X509_EXTENSION_get_object returns const ASN1_OBJECT * */\n    obj = (ASN1_OBJECT *) X509_EXTENSION_get_object(ext);'),
])
# time_to_tm: swap field access for accessors
s = open('nse_ssl_cert.cc').read()
if 'ASN1_STRING_length(t)' not in s:
    a = s.index('static int time_to_tm(')
    b = s.index('static int', a+10)
    body = s[a:b]
    body = body.replace('const unsigned char *p;',
      'const unsigned char *p;\n  int len = ASN1_STRING_length(t);\n  const unsigned char *data = ASN1_STRING_get0_data(t);')
    body = body.replace('t->length','len').replace('t->data','data')
    s = s[:a]+body+s[b:]
s = s.replace('lua_pushlstring(L, (const char *) s->data, s->length);',
  'lua_pushlstring(L, (const char *) ASN1_STRING_get0_data(s), ASN1_STRING_length(s));')
s = s.replace('subject = X509_get_subject_name(cert);',
  '/* OpenSSL 3+/4 returns const X509_NAME *; read-only use below. */\n  subject = (X509_NAME *) X509_get_subject_name(cert);')
s = s.replace('issuer = X509_get_issuer_name(cert);',
  'issuer = (X509_NAME *) X509_get_issuer_name(cert);')
open('nse_ssl_cert.cc','w').write(s)

patch('ncat/ncat_ssl.c', [
 ('    data = asn1_str->data;',
  '    /* OpenSSL 3+/4 made ASN1_OCTET_STRING opaque. */\n    data = (unsigned char *) ASN1_STRING_get0_data(asn1_str);'),
 ('asn1_str_a->length, ASN1_ITEM_ptr(method->it));',
  'ASN1_STRING_length(asn1_str_a), ASN1_ITEM_ptr(method->it));'),
 ('asn1_str_b->length);', 'ASN1_STRING_length(asn1_str_b));'),
])

s = open('nsock/src/nsock_ssl.c').read()
if 'OPENSSL_VERSION_NUMBER < 0x40000000L\n    /* OpenSSL 4 removed' not in s:
    s = s.replace('    OPENSSL_atexit(nsock_ssl_atexit);',
      '#if OPENSSL_VERSION_NUMBER < 0x40000000L\n    /* OpenSSL 4 removed OPENSSL_atexit: the library tears itself down. */\n    OPENSSL_atexit(nsock_ssl_atexit);\n#endif', 1)
    open('nsock/src/nsock_ssl.c','w').write(s)
print("openssl4 patches applied")
PY

# ------------------------------------------------------ config fixes ------
# tcpdump-style false positives (see tcpdump/build.sh) plus libdnet's
# probe ran before the sysroot had sys/sockio.h.
[ -f ios-config.site ] || cp "$root/wget/ios-config.site" ios-config.site
grep -q 'ac_cv_dnet_route_h_has_rt_msghdr' ios-config.site || cat >> ios-config.site <<'EOF'

# --- nmap/libdnet corrections (cross-compile probes all lie) ---
# Darwin/BSD route.h has rt_msghdr -> route-bsd.c is the correct backend;
# the linux_procfs probe falsely succeeds under -undefined dynamic_lookup.
ac_cv_dnet_route_h_has_rt_msghdr=yes
ac_cv_dnet_linux_procfs=no
ac_cv_dnet_linux_interface=no
EOF

make distclean >/dev/null 2>&1 || true
CC="$CC" CXX="$CXXW" AR="$root/tools/darwin-ar" RANLIB="$root/tools/darwin-ranlib" \
    CONFIG_SITE="$PWD/ios-config.site" \
    ./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools \
        --with-libpcap="$PCAP_INST" --with-openssl="$OSSL" \
        --without-libssh2 --without-nping --without-zenmap \
        --without-ndiff --without-nmap-update >/dev/null

# pcre2 as a plain static archive (libtool's dylib branch needs -soname)
( cd libpcre && CC="$CC" CXX="$CXXW" AR="$root/tools/darwin-ar" \
    RANLIB="$root/tools/darwin-ranlib" \
    ./configure --host=armv7-apple-darwin --prefix=/var/mobile/tools \
    --disable-shared --enable-static >/dev/null )

# libdnet backend corrections (see wall list item 3)
sed -i 's/arp-ioctl/arp-bsd/g' libdnet-stripped/src/Makefile
sed -i 's|^/\* #undef HAVE_SYS_SOCKIO_H \*/|#define HAVE_SYS_SOCKIO_H 1|' \
    libdnet-stripped/include/config.h
# nbase's sub-configure also probed through the wrapper (false positive)
sed -i 's|^#define HAVE_STRCASESTR 1$|/* #undef HAVE_STRCASESTR -- iOS libSystem lacks it (device-verified); nbase ships its own */|' \
    nbase/nbase_config.h 2>/dev/null || true

# -------------------------------------------------------------- build ----
# Anything poisoned by an older wrapper run (ASCII dependency lists) has
# to go first: they would otherwise be archived verbatim.
for f in nsock/src/*.o nbase/*.o libnetutil/*.o libz/*.o libpcre/src/*.o libpcre/.libs/*.o libdnet-stripped/src/.libs/*.o *.o; do
    [ -f "$f" ] || continue
    if file -b "$f" 2>/dev/null | grep -q 'ASCII'; then rm -f "$f"; fi
done

make -j"$(nproc)" >/dev/null

# ------------------------------------- repack archives as darwin flat ----
repack() { # repack <archive> <object-dir>
    local a="$1" dir="$2" mems ok=1 m
    [ -f "$a" ] || return 0
    mems=$(llvm-ar-21 t "$a" 2>/dev/null) || return 0
    for m in $mems; do [ -f "$dir/$m" ] || { ok=0; break; }; done
    [ $ok = 1 ] || { echo "skip repack $a (objects missing)" >&2; return 0; }
    ( cd "$dir" && llvm-ar-21 --format=darwin rcs "$(basename $a).new" $mems \
        && mv "$(basename $a).new" "$(basename $a)" )
    echo "repacked $a ($(echo $mems | wc -w) members)"
}
repack nsock/src/libnsock.a        nsock/src
repack nbase/libnbase.a            nbase
repack libnetutil/libnetutil.a     libnetutil
repack libz/libz.a                 libz
repack liblua/liblua.a             liblua
repack liblinear/liblinear.a       liblinear
# pcre2 and libdnet archive their objects inside .libs/
( cd libpcre/.libs 2>/dev/null && [ -f libpcre2-8.a ] && \
    llvm-ar-21 --format=darwin rcs libpcre2-8.a.new pcre2*.o 2>/dev/null \
    && mv libpcre2-8.a.new libpcre2-8.a ) || true
( cd libdnet-stripped/src/.libs 2>/dev/null && [ -f libdnet.a ] && \
    llvm-ar-21 --format=darwin rcs libdnet.a.new *.o \
    && mv libdnet.a.new libdnet.a ) || true

# final link (make may consider things up to date after the repack)
touch nmap.cc; rm -f nmap
make nmap >/dev/null

ldid -S nmap
mkdir -p "$root/out"
cp nmap "$root/out/nmap-$NMAP_VERSION-armv7"
echo "==> $root/out/nmap-$NMAP_VERSION-armv7"
echo "    data files (nmap-services etc) are packaged by make-deb.sh"
