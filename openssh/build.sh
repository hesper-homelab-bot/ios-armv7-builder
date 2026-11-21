#!/bin/bash
# Build OpenSSH portable for armv7 iOS 10.x on Linux.  Verified with 10.6p2
# on an iPad 4 / iOS 10.3.3, run manually (never as a service) on port
# 22223 with auth, shell, scp and sftp all working.
#
# Why 10.6p2 and not something older:
#   * It was the first version tried and it built and ran, so nothing forced a
#     downgrade.  This is recorded as-is rather than dressed up as a survey.
#   * It needs OpenSSL >= 1.1.1; the openssl/ directory already builds 4.0.3
#     for armv7, and libcrypto.a from that build is reused here.
#   * The one thing that would break an older version is not a compile issue
#     but a configure issue: with -undefined dynamic_lookup every
#     AC_CHECK_FUNCS answer is a guess, so each release has to be re-pinned.
#
# The one thing that matters most about this build, and the reason build.sh is
# longer than the others: -undefined dynamic_lookup means the host linker
# accepts a call to any symbol, so *nothing* fails at link time.  Failure shows
# up later as "dyld: lazy symbol binding failed: Symbol not found: _foo" --
# sometimes in a re-exec'd child (sshd-session, sftp-server) that only runs
# after a successful handshake and authentication.  Three of the pins in
# ios-config.site (setproctitle, closefrom, getspnam) were found by running the
# finished binary on the device, not by reading a compile error.
#
# Usage:
#   LD64=.../x86_64-apple-darwin13.4.0-ld LD64_LIBS=... ./build.sh
#   OSSH_VERSION=10.6p2 ./build.sh        # the default
#   PREFIX=/var/mobile/tools ./build.sh   # install prefix baked into paths
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OSSH_VERSION="${OSSH_VERSION:-10.6p2}"
SRC="${OSSH_SRC:-$root/tmp/src/openssh-$OSSH_VERSION}"
OSSL="${OSSL:-$root/tmp/src/openssl-4.0.3}"
PREFIX="${PREFIX:-/var/mobile/tools}"

[ -d "$SRC" ] || {
    read -r U SHA _ <<<"$("$root/tools/fetch-src.sh" --lock openssh)"
    tarball="$("$root/tools/fetch-src.sh" openssh "$U" "$SHA")"
    rm -rf "$SRC"
    tar -C "$root/tmp/src" -xzf "$tarball"
}
[ -d "$SRC" ] || { echo "openssh source layout unexpected" >&2; exit 1; }

# Self-contained dependency (the matrix builds packages on independent
# runners in no particular order)
[ -f "$OSSL/libssl.a" ] || {
    echo "==> building OpenSSL first (openssh's static dependency)"
    (cd "$root/openssl" && ./build.sh)
}
[ -f "$OSSL/libssl.a" ] || { echo "OpenSSL build did not produce $OSSL/libssl.a" >&2; exit 1; }
export IOS_SYSROOT="${IOS_SYSROOT:-$HOME/ios-tool/iPhoneOS10.3.sdk}"
[ -d "$IOS_SYSROOT/usr/include" ] || { echo "missing $IOS_SYSROOT (bootstrap-toolchain.sh stage 3)" >&2; exit 1; }
export IOS_LD64="${IOS_LD64:-${LD64:-$HOME/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld}}"
[ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] || { echo "set IOS_LD64 to the cctools ld64" >&2; exit 1; }

# Must be tmp/stubs: that is where libSystem.tbd actually is.  The repo root is
# what openssl/build.sh and curl/build.sh use, and it does *not* work -- ld64
# answers "library not found for -lSystem" -- it only ever worked because
# those two builds were driven by tmux/build.sh's export_cc(), which sets
# STUBDIR to $WORK/stubs before calling anything.
export IOS_STUBDIR="${IOS_STUBDIR:-$root/tmp/stubs}"
export LD_LIBRARY_PATH="${LD64_LIBS:-}:${LD_LIBRARY_PATH:-}"

# All the "iOS doesn't have this" answers live here.  A config.site rather than
# --cache-file: autoconf rewrites the cache at the end of every run, so
# hand-edited cache values survive exactly one configure.
export CONFIG_SITE="$here/ios-config.site"

# SDK header gaps that are device facts, not configure answers: utimensat(2)
# EXISTS on iOS 10 (proven by openssh's own misc-agent work, which calls it
# with flags=0 and measured success) but the public SDK header does not
# declare it.  A force-included declaration keeps sftp-server's timestamps
# working without lying about anything else.
mkdir -p "$root/tmp/openssh-os-compat"
cat > "$root/tmp/openssh-os-compat.h" <<'EOF'
/* force-included; see the note in openssh/build.sh */
#include <sys/stat.h>
int utimensat(int dirfd, const char *pathname, const struct timespec times[2], int flags);
EOF

# Build a pristine copy so the tarball stays re-extractable and the source
# patches below are unambiguously "done by build.sh".
BUILD="${BUILD:-$root/tmp/openssh-build}"
rm -rf "$BUILD"; mkdir -p "$BUILD"
tar cf - -C "$SRC" . 2>/dev/null | tar xf - -C "$BUILD" || cp -a "$SRC/." "$BUILD/"
cd "$BUILD"
# iOS 10 has no ppoll(2) (dlsym MISS), and openssh 10.6 calls it unconditionally
# in the packet-timeout wait.  The production musl-era binary only survived
# because packet_timeout_ms defaults to -1 and lazy binding never resolved the
# symbol -- a time bomb, not a port.  poll(2) with a millisecond timeout is the
# exact equivalent for a single fd with no signal mask.
python3 - <<'PYEOF'
p = 'packet.c'
t = open(p).read()
old = 'ppoll(&pfd, 1, timespecp, NULL)'
new = 'poll(&pfd, 1, timespecp == NULL ? -1 : (int)(timespecp->tv_sec * 1000 + timespecp->tv_nsec / 1000000))'
n = t.count(old)
t = t.replace(old, new)
open(p, 'w').write(t)
print('    packet.c ppoll -> poll sites replaced:', n)
# every other ppoll(2) call site, across every shape (clientloop/serverloop/
# ssh-agent/sshd/ssh-keyscan): poll(2) with the timeout converted to
# milliseconds, signal mask dropped (the kit never passes one that matters --
# each site's handler is self-resetting)
import glob, re
n2 = 0
for f in glob.glob('*.c'):
    t = open(f).read()
    orig = t
    t = t.replace('ppoll(*pfdp, *npfd_activep, ptimeout_get_tsp(&timeout), sigsetp)',
        'poll(*pfdp, *npfd_activep, (int)(timeout.tv_sec * 1000 + timeout.tv_nsec / 1000000))')
    t = t.replace('ppoll(pfd, npfd, ptimeout_get_tsp(&timeout), &osigset)',
        'poll(pfd, npfd, (int)(timeout.tv_sec * 1000 + timeout.tv_nsec / 1000000))')
    t = t.replace('ppoll(pfd, npfd, NULL, &osigset)',
        'poll(pfd, npfd, -1)')
    t = t.replace('ppoll(read_wait, maxfd, &seltime, NULL)',
        'poll(read_wait, maxfd, (int)(seltime.tv_sec * 1000 + seltime.tv_nsec / 1000000))')
    if t != orig:
        open(f, 'w').write(t)
        n2 += 1
print('    ppoll files patched:', n2)
# setresgid/setresuid: the device has neither (dlsym MISS); every call site
# passes the same value three times, so setgid/setuid are exact equivalents
n3 = 0
for f in glob.glob('*.c'):
    t = open(f).read()
    orig = t
    t = t.replace('setresgid(pw->pw_gid, pw->pw_gid, pw->pw_gid)', 'setgid(pw->pw_gid)')
    t = t.replace('setresuid(pw->pw_uid, pw->pw_uid, pw->pw_uid)', 'setuid(pw->pw_uid)')
    t = t.replace('setresgid(getegid(), getegid(), getegid())', 'setgid(getegid())')
    t = t.replace('setresuid(geteuid(), geteuid(), geteuid())', 'setuid(geteuid())')
    if t != orig:
        open(f, 'w').write(t)
        n3 += 1
print('    setres files patched:', n3)
p = 'misc.c'
t = open(p).read()
n2 = t.count('ppoll(&pfd, 1, ptimeout_get_tsp(&timeout),\n\t\t    stop != NULL ? &osigset : NULL)')
if n2:
    # poll with a millisecond timeout computed from the timespec; the signal
    # mask argument has no poll(2) equivalent, but the ppoll call site here is
    # only reached from the *timeout variant of this helper, which the kit
    # never exercises with a signal mask
    t = t.replace('r = ppoll(&pfd, 1, ptimeout_get_tsp(&timeout),\n\t\t    stop != NULL ? &osigset : NULL)',
        'r = poll(&pfd, 1, (int)(timeout.tv_sec * 1000 + timeout.tv_nsec / 1000000))')
    open(p, 'w').write(t)
    print('    misc.c ppoll sites replaced:', n2)
# setresgid/setresuid in misc.c's privilege-drop helper: the device has neither
# (dlsym MISS); plain setgid/setuid are the portable equivalents and the saved-
# id third argument is unused by every caller here (all three args identical)
t = open(p).read()
n3 = 0
for fn, alt in (('setresgid', 'setgid'), ('setresuid', 'setuid')):
    call = '%s(pw->pw_%s, pw->pw_%s, pw->pw_%s)' % (fn, 'gid' if fn.endswith('gid') else 'uid', 'gid' if fn.endswith('gid') else 'uid', 'gid' if fn.endswith('gid') else 'uid')
    if call in t:
        t = t.replace(call, '%s(pw->pw_%s)' % (alt, 'gid' if fn.endswith('gid') else 'uid'))
        n3 += 1
open(p, 'w').write(t)
print('    misc.c setres* sites replaced:', n3)
PYEOF

make distclean >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Source patches that cannot be expressed as configure answers.
#
# iOS 10 accepts no *at() flags at all.  Measured on the device by driving
# fstatat/fchmodat/utimensat/fchownat with each of {0, 0x100, 0x1000, 0x2,
# 0x800}: every call with a non-zero flag returned EINVAL, and every call with
# flag 0 succeeded.  (Darwin's real values are 0x100 for AT_SYMLINK_NOFOLLOW,
# which musl does not define at all -- its <fcntl.h> has no AT_* constants.
# OpenSSH only defines AT_SYMLINK_NOFOLLOW itself in the branch where it has to
# supply its own utimensat(); iOS has utimensat, so that branch is not taken
# and the macro simply does not exist.)
#
# So: define it as 0, in the source, with the reason recorded.  Nothing is
# lost -- the flag was never supported.
if ! grep -q '^/\* iOS: AT_.\* flags are 0 (see openssh/build.sh)' misc-agent.c; then
    python3 - misc-agent.c <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "&sb, AT_SYMLINK_NOFOLLOW) != 0 && errno != ENOVENT"
if old not in s:
    old = "&sb, AT_SYMLINK_NOFOLLOW) != 0 && errno != ENOENT"
assert old in s, "misc-agent.c: fstatat site not found"
s = s.replace(old, old.replace("AT_SYMLINK_NOFOLLOW", "0"))
open(p, "w").write(s)
print("    patched misc-agent.c: fstatat flag -> 0")
PY
fi
if ! grep -q '^/\* iOS: AT_.\* flags are 0 (see openssh/build.sh)' sftp-server.c; then
    python3 - sftp-server.c <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
n = s.count("AT_SYMLINK_NOFOLLOW")
assert n == 3, "expected 3 AT_SYMLINK_NOFOLLOW sites in sftp-server.c, got %d" % n
s = s.replace("AT_SYMLINK_NOFOLLOW", "0")
open(p, "w").write(s)
print("    patched sftp-server.c: 3 *at() flags -> 0")
PY
fi

# port-net.c's SSH_TUN_FREEBSD branch (configure's *-*-darwin* case defines
# it -- macOS opens tunnels the FreeBSD way) includes <net/if.h> and then
# uses SIOCSIFFLAGS/SIOCGIFFLAGS.  The sysroot's net/if.h does NOT pull in
# sys/sockio.h (Darwin's does), so the ioctl request macros are undeclared.
# iOS has no /dev/tun* anyway -- the branch is dead code here -- but it must
# still compile.  One include fixes it (idempotent).
if ! grep -q 'iOS: sockio for SIOC' openbsd-compat/port-net.c; then
    python3 - openbsd-compat/port-net.c <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "#ifdef SSH_TUN_FREEBSD\n#include <sys/socket.h>\n#include <net/if.h>"
assert old in s, "port-net.c: SSH_TUN_FREEBSD include block not found"
s = s.replace(old, old + "\n#include <sys/sockio.h> /* iOS: sockio for SIOC* (net/if.h does not pull it in) */", 1)
open(p, "w").write(s)
print("    patched port-net.c: include sys/sockio.h")
PY
fi

# ---------------------------------------------------------------------------
# Configure.
#
# --with-ssl-dir points at the OpenSSL *build tree*, not an install tree, so
# configure does not try to run the cross-compiled openssl binary to get a
# version number (an armv7 binary cannot execute on the Linux host; that is
# the "single hard blocker" mentioned in dropbear/build.sh, and this is how it
# is dodged rather than solved).
#
# -DOPENSSL_API_COMPAT=0x10100000L is what configure itself adds when it can
# detect OpenSSL 3.x/4.x; here it cannot run that probe, so it is passed in by
# hand.  Without it OpenSSL 4 headers hide the 1.1-era declarations OpenSSH
# uses and the build dies in cipher.c on EVP_CIPHER_CTX_get_iv.
#
# -DDISABLE_SHADOW is the OpenSSH-blessed way to turn off shadow passwords.
# musl's <shadow.h> declares getspnam() and <fcntl.h>/<unistd.h> make the link
# test pass, but iOS exports neither getspnam() nor anything else from the
# shadow family (its account data lives in OpenDirectory).  The symptom without
# this define is a *successful* key exchange, a *successful* publickey
# authentication, and then sshd-session aborting with "Symbol not found:
# _getspnam" -- the client only sees "Connection closed".
#
# --with-privsep-user=_sshd is required for sshd to run *as root*, which is
# what a LaunchDaemon does.  OpenSSH's default is a nonexistent-on-iOS account
# named plain "sshd", and the failure is only that -- sshd refuses to start
# before it ever binds a socket:
#     sshd: PrivDropPrivilege: fatal: chroot("/var/empty"): No such file or
#         directory          <- when /var/empty is missing
#     ...
#     Privilege separation user sshd does not exist.
# Running the same binary as an unprivileged user (mobile, uid 501) works,
# because then privsep is not entered at all -- so the bug is invisible until
# launchd starts it as root.  iOS *does* ship exactly this user, as `_sshd`
# (uid 75, home /var/empty, shell /usr/bin/false):
#     _sshd:*:75:75:sshd Privilege separation:/var/empty:/usr/bin/false
# so "sshd does not exist" is a compile-time answer, not a device fact.  The
# chroot directory is left at the default /var/empty, which exists on the
# device (drwxr-xr-x root:sys), so --with-privsep-path is not needed.
CC="$root/tools/cc-wrapper.sh" AR="$root/tools/darwin-ar" \
RANLIB="$root/tools/darwin-ranlib" \
CFLAGS="-DDISABLE_SHADOW -DOPENSSL_API_COMPAT=0x10100000L \
 -include $root/tmp/openssh-os-compat.h" \
./configure --host=armv7-apple-darwin --build=x86_64-pc-linux-gnu \
    --prefix="$PREFIX" \
    --with-privsep-user=_sshd \
    --with-ssl-dir="$OSSL" \
    --without-zlib --without-pam --without-libedit \
    --without-selinux --without-libaudit --without-wtmpdb \
    --without-ldns --without-prngd-socket \
    --disable-strip \
    >/dev/null

# Archive resolution fix (2026-11-13, refined): bcrypt_pbkdf.o lives in
# libopenbsd-compat.a and references blf_enc from blowfish.o in the SAME
# archive.  ld64 scans each archive exactly ONCE -- bcrypt_pbkdf.o is pulled
# because libssh.a (earlier) needed it, and the resulting blf_enc undefined
# finds no later archive: re-appending -lopenbsd-compat does NOT help (same
# archive, already scanned).  Naming blowfish.o as an explicit OBJECT does:
# object files are always loaded, never positionally skipped.  This is the
# path that decrypts passphrase-protected private keys.
sed -i 's|^LIBS=\(.*\)$|LIBS=\1 openbsd-compat/blowfish.o|' Makefile
grep -q "openbsd-compat/blowfish.o" Makefile || {
    echo "LIBS blowfish.o sed did not apply" >&2; exit 1
}
# sshd's code paths make the compiler emit ___atomic_is_lock_free, the ONE
# atomic helper the device libSystem lacks (dlsym MISS).  Reuse openssl's
# spinlock compat (asm label pins the symbol exactly).
ACOBJ="$root/tmp/openssh-atomic-compat.o"
"$root/tools/cc-wrapper.sh" -c "$root/openssl/atomic_compat.c" -o "$ACOBJ"
sed -i "s|^LIBS=\(.*\)$|LIBS=\1 $ACOBJ|" Makefile
grep -q "atomic-compat.o" Makefile || {
    echo "LIBS atomic-compat sed did not apply" >&2; exit 1
}

make -j"$(nproc)" >/dev/null

# What to copy out.  The four sshd-side binaries are the ones a working
# sshd needs: sshd re-execs sshd-session for the post-auth phase and
# sshd-auth when privilege separation is on, and sftp-server backs both scp
# and sftp.  The rest are the client tools.
for p in sshd sshd-session sshd-auth ssh-keysign ssh-pkcs11-helper \
         ssh-sk-helper ssh ssh-add ssh-keygen ssh-agent ssh-keyscan \
         scp sftp sftp-server; do
    [ -f "$p" ] || { echo "$p was not built" >&2; exit 1; }
done

# ---------------------------------------------------------------- sanity gate
# A last check that catches the class of bug this whole exercise is about:
# undefined symbols that only the device can resolve.  Cross-check every
# undefined symbol against a "known absent on iOS 10" list derived from
# probing the device.  Anything in that list is a runtime dyld abort.
python3 - <<'PY'
import os, shutil, subprocess, sys
# Verified ABSENT on the device by compiling a caller and running it.  These
# are the ones that *were* wired into OpenSSH and had to be pinned in
# ios-config.site so the project's own portable fallback would be built.
ABSENT = {
    "accept4", "pipe2", "eventfd", "epoll_wait", "getrandom", "prctl",
    "close_range",
    "setresgid", "setresuid", "clearenv", "freezero", "recallocarray",
    "reallocarray", "strtonum", "bcrypt_pbkdf", "explicit_bzero",
    "ptsname_r", "getexecpath", "setproctitle", "pledge", "unveil",
    "getlastlogxbyname", "getspnam", "scan_scaled", "fmt_scaled",
    "b64_ntop", "b64_pton", "updwtmpx", "logwtmp", "login", "logout",
    "utmpname", "getutent",
    "ns_initparse", "ns_name_uncompress",
}
# Liabilities that remain but are not reachable, explained in ../README.md:
# they come from OpenSSL's own BIO datagram layer, dragged in by
# libssl-lib-ssl_lib.o's reference to BIO_s_datagram, and by OpenSSH's
# getrrsetbyname.c for the low-level ns_get* calls.  Nothing in the paths
# this build exercises ever calls them, which is why a real login, scp and
# sftp all work with them still undefined -- dyld only resolves lazily.  The
# gate therefore reports them but does not fail the build.
KNOWN_UNRESOLVED = {
    "recvmmsg", "sendmmsg",          # OpenSSL libcrypto-lib-bss_dgram.o
    "ns_get16", "ns_get32",          # OpenSSH openbsd-compat/getrrsetbyname.o
}
bad, warn = [], []
for b in ("sshd", "sshd-session", "sshd-auth", "sftp-server", "ssh", "scp"):
    if not os.path.exists(b):
        continue
    nm = shutil.which("llvm-nm-21") or shutil.which("llvm-nm") or "llvm-nm"
    res = subprocess.run([nm, "--undefined-only", b],
                         capture_output=True)
    out = res.stdout.decode("utf-8", "replace")
    for line in out.splitlines():
        parts = line.split()
        if not parts:
            continue
        sym = parts[-1]
        if not sym.startswith("_"):
            continue
        name = sym[1:]
        if name in ABSENT:
            bad.append((b, name))
        elif name in KNOWN_UNRESOLVED:
            warn.append((b, name))
for b, n in warn:
    print("    note: still undefined but unreachable: %s: _%s" % (b, n))
if bad:
    for b, n in bad:
        print("    FAIL: undefined and absent on iOS: %s: _%s" % (b, n))
    sys.exit(1)
print("    no iOS-absent symbols left undefined")
PY

# Whitelist-mode audit (tools/check-undefined.sh): complements the ABSENT
# gate above, which only reports symbols a hand-maintained list already
# knows about -- that list never knew about blf_enc, so a whole release
# shipped with it undefined.  Anything not provably device-provided fails
# the build here.
for p in sshd sshd-session sshd-auth ssh ssh-add ssh-keygen ssh-agent \
         ssh-keyscan ssh-keysign ssh-pkcs11-helper ssh-sk-helper \
         scp sftp sftp-server; do
    [ -f "$p" ] || continue
    "$root/tools/check-undefined.sh" "$p"
done

mkdir -p "$root/out"
for p in sshd sshd-session sshd-auth ssh ssh-add ssh-keygen ssh-agent \
         ssh-keyscan ssh-keysign ssh-pkcs11-helper ssh-sk-helper \
         scp sftp sftp-server; do
    [ -f "$p" ] || continue
    cp "$p" "$root/out/openssh-$p-$OSSH_VERSION-armv7"
done

echo "==> $root/out/openssh-*-$OSSH_VERSION-armv7"
echo "    arch:   $(file -b sshd | cut -d, -f1)"
echo
echo "    Install and run MANUALLY (never as a launchd daemon):"
echo "      mkdir /var/mobile/tools-osshtest && cp $root/out/openssh-*-$OSSH_VERSION-armv7 /var/mobile/tools-osshtest/"
echo "      # rename on the device with the ossh- prefix (see README) and ldid -S each one"
echo "      /var/mobile/tools-osshtest/ossh-sshd -D -e -f /path/to/sshd_config"
echo
echo "    sshd_config must point at the re-exec binaries and the host key:"
echo "      SshdSessionPath /var/mobile/tools-osshtest/ossh-sshd-session"
echo "      SshdAuthPath     /var/mobile/tools-osshtest/ossh-sshd-auth"
echo "      Subsystem sftp   /var/mobile/tools-osshtest/ossh-sftp-server"
echo
echo "    --with-privsep-path is NOT used: sshd refuses to run without a root-"
echo "    owned chroot directory, and installing one would mean touching /var"
echo "    as root.  Run sshd as the invoking user instead; authentication then"
echo "    cannot drop privileges to other users and stays on publickey."
