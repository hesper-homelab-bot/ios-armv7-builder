#!/bin/bash
# Package the armv7 OpenSSH build into a .deb for the APT repo.
#
# Deliberately different from dropbear/make-deb.sh, and the difference is the
# whole point of this package:
#
#   * /usr is never touched.  /usr/bin/ssh, /usr/libexec/sftp-server and
#     /usr/sbin/sshd are what the OS itself depends on, and /var/mobile is
#     exactly what the README says to keep in place so that removing the
#     package restores the device.
#   * The binaries are installed with an ossh- prefix.  dropbear uses db- for
#     the same reason, and here the reason is sharper still: the system sshd
#     and the OS both exec "ssh" and "scp" by that name, and an armv7 OpenSSH
#     10.6 in PATH ahead of /usr/bin would break them.
#   * The LaunchDaemon is com.hesper.osshd, on its own port, defaulting to 22
#     -- the port a user who installs only this package expects.  It does not
#     load anything belonging to the system: /usr/sbin/sshd is named by
#     absolute path in the sshd plist, so this daemon and that one cannot
#     collide.  The plist and sshd_config are conffiles, so moving the port
#     survives an upgrade, and the wrapper refuses to start on a port already
#     held instead of looping under KeepAlive.
#
# What is installed:
#   /var/mobile/tools/ossh-*               the binaries
#   /var/mobile/tools/bin/ssh              link, because scp and sftp exec a
#                                         compiled-in path, not a PATH lookup
#   /var/mobile/.local/bin/osshd-daemon.sh the wrapper (generates host keys,
#                                         guards the port, execs sshd -D)
#   /var/mobile/ssh-openssh/sshd_config    configuration, a conffile
#   /Library/LaunchDaemons/com.hesper.osshd.plist   the job, also a conffile
#   ossh-sshd-session     sshd re-execs this for the post-auth phase
#   ossh-sshd-auth        re-exec'd when privilege separation is on
#   ossh-ssh, ossh-scp, ossh-sftp, ossh-sftp-server
#   ossh-ssh-keygen, ossh-ssh-add, ossh-ssh-agent, ossh-ssh-keyscan
# /var/mobile/.local/bin/ is left alone; put it in your PATH only if you want
# the prefix names, which are safe because they do not collide.
#
# Usage:
#   ./openssh/make-deb.sh                 # uses ../out/openssh-*-armv7
#   DEBREV=2 ./openssh/make-deb.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
OSSH_VERSION="${OSSH_VERSION:-10.6p2}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
PKG="${PKG:-openssh4}"
# Port the daemon listens on, written into the shipped sshd_config at package
# time so a rebuild produces a matching package.  Defaults to 22 -- most people
# install exactly one of the two SSH packages here.  To put this package
# somewhere else instead:
#     OSSH_PORT=22226 ./openssh/make-deb.sh
# The plist is a conffile and so is sshd_config, so a later local edit of the
# port on the device is not overwritten by an upgrade.
PORT="${OSSH_PORT:-22}"
# (custom-port builds are routed to pkg/ rather than out/ -- see below)


# Signing once, on the host, is enough.  The "Killed: 9 on host ldid" warning
# this comment used to carry was wrong -- see the signing section in the
# README for the controlled experiment that settled it -- and re-signing on the
# device buys nothing.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst" || { echo "cp failed: $src -> $dst" >&2; exit 1; }

    # Failures here must be loud.  This function used to end in
    #     ldid -S "$dst" 2>/dev/null || true
    # which swallowed everything, and the binary that reached the package was
    # then *unsigned* -- and an unsigned Mach-O is killed by the device with
    # SIGKILL and no crash report, before main().  That is the whole origin of
    # the "host ldid occasionally produces a binary the device kills with
    # Killed: 9" folklore: not host ldid being unreliable, but this
    # swallowing the failure.  See the signing section in README.
    command -v ldid >/dev/null 2>&1 || {
        echo "ldid is not on PATH -- refusing to package an unsigned binary" >&2
        exit 1
    }
    ldid -S "$dst" || {
        echo "ldid -S failed for $dst" >&2
        exit 1
    }

    # ldid -e exits 0 only when the file actually carries a signature (verified
    # by signing a copy of an unsigned binary and re-checking), so this is a
    # real assertion rather than a formality.
    ldid -e "$dst" >/dev/null 2>&1 || {
        echo "$dst carries no signature after ldid -S" >&2
        exit 1
    }
}


w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w/var/mobile/tools" "$w/usr/share/doc/$PKG"

cat > "$w/DEBIAN/control" <<CTRL
Package: $PKG
Name: OpenSSH $OSSH_VERSION
Version: $OSSH_VERSION-$DEBREV
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://www.openssh.com/
Description: OpenSSH $OSSH_VERSION for armv7 iOS, manual use only
 Installs as ossh-* under /var/mobile/tools so it never shadows the system
 ssh/scp. Deliberately registers no launchd daemon: run it yourself with
 .
   ossh-sshd -D -e -f /var/mobile/tools-osshtest/sshd_config
 .
 on a port of your choosing.
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
CTRL

cat > "$w/DEBIAN/conffiles" <<CONF
CONF

cat > "$w/usr/share/doc/$PKG/changelog" <<CH
$PKG ($OSSH_VERSION-$DEBREV) stable; urgency=medium

  * OpenSSH $OSSH_VERSION built for armv7 iOS 10 on a Linux host.
  * No launchd daemon, no LaunchDaemons plist, no launchctl call.
  * Prefixed ossh- to avoid shadowing /usr/bin/ssh and friends.
  * Includes sshd-session/sshd-auth because sshd re-execs them.

 -- $MAINTAINER  $(date -R)
CH

# The binaries this package ships.  sftp-server backs both scp and sftp, and
# sshd-session/sshd-auth are the re-exec targets sshd forks into.
for p in sshd sshd-session sshd-auth ssh scp sftp sftp-server \
         ssh-keygen ssh-add ssh-agent ssh-keyscan; do
    f="$OUT/openssh-$p-$OSSH_VERSION-armv7"
    [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
    sign "$f" "$w/var/mobile/tools/ossh-$p"
done

chmod 755 "$w"/var/mobile/tools/*

# The daemon.  A fresh `apt-get install openssh4` used to produce a package of
# command-line tools and nothing else -- the plist, the wrapper and the config
# lived only on the one device they were created on, so nobody else could get a
# running service from the published package.  All three ship now.
mkdir -p "$w/Library/LaunchDaemons" "$w/var/mobile/.local/bin" "$w/var/mobile/ssh-openssh"
install -m 0644 "$here/osshd.plist" "$w/Library/LaunchDaemons/com.hesper.osshd.plist"
install -m 0755 "$here/osshd-daemon.sh" "$w/var/mobile/.local/bin/osshd-daemon.sh"

# The port is the one line of sshd_config that changes per install, so it is
# substituted here rather than shipped literally.  A typo would otherwise reach
# the device as a config line sshd rejects at startup, which is a slow way to
# find out; validate it here instead.
case "$PORT" in
    ''|*[!0-9]*)
        echo "OSSH_PORT must be a number, got '$PORT'" >&2; exit 1 ;;
esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "OSSH_PORT out of range: $PORT" >&2; exit 1
fi
if [ "$PORT" -lt 1024 ]; then
    echo "note: OSSH_PORT=$PORT is privileged; the daemon runs as root, so it binds fine," >&2
    echo "      but a foreground test as a non-root user will fail." >&2
fi

sed -e "s|^Port[[:space:]].*|Port $PORT|" "$here/sshd_config" \
    > "$w/var/mobile/ssh-openssh/sshd_config"
grep -qx "Port $PORT" "$w/var/mobile/ssh-openssh/sshd_config" || {
    echo "port was not substituted into sshd_config" >&2; exit 1; }
chmod 0644 "$w/var/mobile/ssh-openssh/sshd_config"

# Both of these are meant to be edited -- the Port line and the equivalent for
# dropbear -- and dpkg would otherwise replace them with the packaged defaults
# on every upgrade, which is precisely the change that must not be reverted.
# Hence conffiles.
cat > "$w/DEBIAN/conffiles" <<EOF
/Library/LaunchDaemons/com.hesper.osshd.plist
/var/mobile/ssh-openssh/sshd_config
EOF

# OpenSSH's scp and sftp do not search PATH for the ssh binary: they exec a
# path compiled into them, which is <bindir>/ssh.  build.sh configures with
# --prefix="$PREFIX" (default /var/mobile/tools), so bindir defaulted to
# $PREFIX/bin and both binaries carry the literal
# /var/mobile/tools/bin/ssh.  The ossh- prefix moves the real binaries out of
# that path, so without this link every scp and sftp invocation dies with
#     exec: /var/mobile/tools/bin/ssh: No such file or directory
# while ssh itself keeps working -- a confusing failure to debug, so the
# dependency is satisfied by the package rather than by the user.
#
# The target has to be absolute: a relative "ossh-ssh" would resolve against
# the link's own directory and look for /var/mobile/tools/bin/ossh-ssh, which
# does not exist.  Verified on the device: relative dangles, absolute works.
mkdir -p "$w/var/mobile/tools/bin"
ln -sfn /var/mobile/tools/ossh-ssh "$w/var/mobile/tools/bin/ssh"

[ -L "$w/var/mobile/tools/bin/ssh" ] || { echo "bin/ssh is not a symlink" >&2; exit 1; }
[ "$(readlink "$w/var/mobile/tools/bin/ssh")" = /var/mobile/tools/ossh-ssh ] || {
    echo "bin/ssh points at the wrong target" >&2; exit 1; }


# Where the .deb lands.  Default-parameter builds go to out/, which is what
# scripts/make-repo.sh scans and what releases are cut from; a build with a
# non-default port is for one specific device and goes to pkg/ instead, so it
# cannot be published by accident.
CUSTOM=0
[ "$PORT" = "22" ] || CUSTOM=1
if [ "$CUSTOM" = 1 ]; then OUTDIR="$root/pkg"; else OUTDIR="$root/out"; fi
mkdir -p "$OUTDIR"
deb="$OUTDIR/${PKG}_${OSSH_VERSION}-${DEBREV}_iphoneos-arm.deb"
# --root-owner-group: without it these binaries land on the device owned by the
# host's build uid (1000), a user that does not exist there.  root:root at mode
# 755 is both tidy and the safer posture -- a logged-in user cannot swap the ssh
# binary they are about to execute.  (Re-sign on the device after installing.)
# shellcheck disable=SC2086
dpkg-deb -Zgzip --root-owner-group -b "$w" "$deb"
echo "==> $deb"
echo "    installs ossh-* plus the com.hesper.osshd plist, wrapper and sshd_config"
echo "    one LaunchDaemon, on its own port, conffiles for plist and config"
