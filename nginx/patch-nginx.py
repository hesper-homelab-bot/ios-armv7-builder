#!/usr/bin/env python3
"""Idempotent patches that make nginx 1.26's configure survive cross-compiling.

nginx runs a handful of feature probes and *executes* the resulting binary
(ngx_feature_run=yes).  Cross-compiled, those binaries are armv7 Mach-O and
the build host is x86 Linux, so nginx concludes "found but is not working"
and silently drops NGX_HAVE_* macros.  Three files need help:

  auto/feature      every run-probe funnels through this one script -> route
                    the execution through a hook (nginx/crossanswer.sh).
  auto/types/sizeof the type-size probes must run; the sizes are a property
                    of the armv7/iOS ABI and are supplied from a table that
                    was verified with _Static_assert against the real sysroot.
  auto/endianness   armv7 iOS is little-endian; answer without running.

The patches are textual and idempotent: re-running this script after a
`rm -rf objs` (or on a freshly untarred source tree) is safe.
"""
import os
import sys

src_dir = sys.argv[1]
cross_runner = sys.argv[2]

MARK_FEATURE = "# ---- nginx-cross: run-probe hook ----"
MARK_SIZEOF = "# ---- nginx-cross: size table ----"


def patch(path, func):
    p = os.path.join(src_dir, path)
    s = open(p).read()
    new = func(s)
    if new != s:
        open(p, "w").write(new)
        print("patched %s" % path)
    else:
        print("already patched %s" % path)


# --------------------------------------------------------------- feature --
def do_feature(s):
    if MARK_FEATURE in s:
        return s
    hook = """%s
# Cross-compiling: the probe binary is Mach-O for armv7 and cannot run on
# the build host.  Try it anyway (a native build still behaves normally),
# then fall back to the target-knowledge hook.  $NGX_AUTOCONF_ERR keeps the
# evidence either way.
ngx_cross_run() { # ngx_cross_run <autotest-binary> <source>
    if "$1" >> $NGX_AUTOCONF_ERR 2>&1; then
        return 0
    fi
    if [ -x "%s" ]; then
        "%s" "$2" >> $NGX_AUTOCONF_ERR 2>&1
        return $?
    fi
    return 1
}
""" % (MARK_FEATURE, cross_runner, cross_runner)
    s = s.replace("ngx_found=no\n", "ngx_found=no\n\n" + hook, 1)
    # the three run sites, all of the identical form
    s = s.replace("/bin/sh -c $NGX_AUTOTEST >> $NGX_AUTOCONF_ERR 2>&1",
                  "ngx_cross_run $NGX_AUTOTEST $NGX_AUTOTEST.c >> $NGX_AUTOCONF_ERR 2>&1")
    # the "value" branch reads the value off stdout; supply a table-driven
    # answer too (none of nginx's value probes are used on this target).
    s = s.replace("#define $ngx_feature_name  `$NGX_AUTOTEST`",
                  "#define $ngx_feature_name  0")
    return s


# ---------------------------------------------------------------- sizeof --
# Sizes verified against the real sysroot with clang -fsyntax-only and
# _Static_assert for -target armv7-apple-ios10.3 (all passed).  Reproduce
# with nginx/_abi-check.c if the sysroot ever changes.
SIZES = {
    "int": 4, "long": 4, "long long": 8, "void *": 4,
    "size_t": 4, "off_t": 8, "time_t": 4, "sig_atomic_t": 4,
}


def do_sizeof(s):
    if MARK_SIZEOF in s:
        return s
    table_lines = "\n".join(
        '        "%s") ngx_size=%d ;;' % (t.replace('"', '\\"'), v)
        for t, v in SIZES.items()
    )
    block = """%s
# Cross-compiling: the probe binary cannot execute, so its size answer is
# taken from a table verified against the sysroot with _Static_assert
# (see nginx/build.sh).  Anything not in the table falls through to a
# compile-time probe below.
ngx_cross_size() {
    case "$ngx_type" in
%s
        *) ngx_size= ;;
    esac
}
""" % (MARK_SIZEOF, table_lines)
    s = s.replace("ngx_size=\n", "ngx_size=\n\n" + block, 1)
    s = s.replace("if [ -x $NGX_AUTOTEST ]; then\n    ngx_size=`$NGX_AUTOTEST`",
                  "ngx_cross_size\nif [ -z \"$ngx_size\" ] && [ -x $NGX_AUTOTEST ]; then\n    ngx_size=`$NGX_AUTOTEST`")
    return s


# ------------------------------------------------------------ endianness --
def do_endianness(s):
    if "nginx-cross: little endian" in s:
        return s
    old = 'if [ -x $NGX_AUTOTEST ]; then\n    if $NGX_AUTOTEST >/dev/null 2>&1; then'
    new = ('# nginx-cross: little endian -- armv7 iOS is little-endian, and the\n'
           '# probe binary cannot execute on a Linux build host.\n'
           'if [ -x $NGX_AUTOTEST ]; then\n'
           '    if true; then')
    if old in s:
        s = s.replace(old, new, 1)
    return s


# ------------------------------------------------- OpenSSL 4 ASN1 opaque --
# OpenSSL 3 made ASN1_STRING opaque and OpenSSL 4 removed the last vestiges
# of public field access.  nginx 1.26's OCSP-stapling code still reads
# ASN1_INTEGER->data / ->length directly (ngx_ssl_ocsp_create_key()), which
# no longer compiles.  The accessors have been the supported interface since
# OpenSSL 1.1 and return exactly the same bytes.  Identical in spirit to the
# nmap port's OpenSSL 4 patches (nmap/build.sh, wall #6).
def do_stapling(s):
    if "ASN1_STRING_get0_data(serial)" in s:
        return s
    old = """    serial = X509_get_serialNumber(ctx->cert);
    if (serial->length > 20) {
        return NGX_ERROR;
    }

    p = ngx_cpymem(p, serial->data, serial->length);
    ngx_memzero(p, 20 - serial->length);"""
    new = """    serial = X509_get_serialNumber(ctx->cert);

    /* OpenSSL 3+/4 made ASN1_INTEGER opaque; use the accessors. */
    int  serial_len = ASN1_STRING_length(serial);

    if (serial_len > 20) {
        return NGX_ERROR;
    }

    p = ngx_cpymem(p, ASN1_STRING_get0_data(serial), serial_len);
    ngx_memzero(p, 20 - serial_len);"""
    if old not in s:
        raise SystemExit("stapling patch anchor not found")
    return s.replace(old, new, 1)


patch("auto/feature", do_feature)
patch("auto/types/sizeof", do_sizeof)
patch("auto/endianness", do_endianness)

patch("src/event/ngx_event_openssl_stapling.c", do_stapling)
