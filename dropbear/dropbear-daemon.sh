#!/bin/sh
# Dropbear daemon wrapper for the iPad 4 (iOS 10.3.3).
#
# Installed as /var/mobile/.local/bin/dropbear-daemon.sh and started by the
# LaunchDaemon com.hesper.dropbear (see dropbear-daemon.plist).
#
# Why a wrapper at all:
#
#   * iOS's own sshd is started through /usr/libexec/sshd-keygen-wrapper,
#     which generates the host keys if they are missing.  Dropbear has no
#     such thing, and a missing host key makes it exit immediately -- which
#     launchd would then retry forever, silently.  Generating them here makes
#     a fresh install work with no manual step.
#   * Dropbear daemonises itself unless -F is given, and launchd can only
#     supervise a process that stays in the foreground, so the binary is
#     exec'd with -F.
#
# This daemon deliberately listens on port 2222 and never touches
# /usr/sbin/sshd on port 22: SSH is the only remote access to this device, so
# the old server stays running until a cutover is explicitly decided.
set -u

BINDIR=/var/mobile/tools
KEYDIR=/var/mobile/ssh
DROPBEAR="$BINDIR/db-dropbear"
DROPBEARKEY="$BINDIR/db-dropbearkey"
PORT="${DROPBEAR_PORT:-2222}"

log() {
    echo "dropbear-daemon: $*"
}

# Generate host keys on first run.  ed25519 is preferred; rsa is kept as well
# because some old clients (including this device's own OpenSSH 6.7p1 client)
# cannot do ed25519.
[ -x "$DROPBEAR" ] || { log "missing $DROPBEAR"; exit 1; }
[ -x "$DROPBEARKEY" ] || { log "missing $DROPBEARKEY"; exit 1; }

if [ ! -s "$KEYDIR/host_ed25519" ]; then
    log "generating ed25519 host key"
    mkdir -p "$KEYDIR"
    "$DROPBEARKEY" -t ed25519 -f "$KEYDIR/host_ed25519" >/dev/null 2>&1 || log "ed25519 keygen failed"
fi

if [ ! -s "$KEYDIR/host_rsa" ]; then
    log "generating rsa host key"
    mkdir -p "$KEYDIR"
    "$DROPBEARKEY" -t rsa -s 2048 -f "$KEYDIR/host_rsa" >/dev/null 2>&1 || log "rsa keygen failed"
fi

# -F foreground (launchd supervises), -E log to stderr, -r may repeat.
# DROPBEAR_EXTRA_ARGS is available for one-off experiments such as -v.
# shellcheck disable=SC2086
exec "$DROPBEAR" -F -E -p "$PORT" \
    -r "$KEYDIR/host_ed25519" \
    -r "$KEYDIR/host_rsa" \
    ${DROPBEAR_EXTRA_ARGS:-}
