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
# Port layout: DROPBEAR_PORT is the primary listener (22) and
# DROPBEAR_EXTRA_ARGS carries a second -p as a fallback, so the port this
# daemon was installed and verified on stays reachable even if the primary
# regresses.  SSH is the only remote access to this device, which is exactly
# why the fallback is never dropped without a deliberate decision.
set -u

BINDIR=/var/mobile/tools
KEYDIR=/var/mobile/ssh
DROPBEAR="$BINDIR/db-dropbear"
DROPBEARKEY="$BINDIR/db-dropbearkey"
PORT="${DROPBEAR_PORT:-22}"

log() {
    echo "dropbear-daemon: $*"
}

# Refuse to start on a port something already holds, and say what holds it.
#
# Both SSH packages here default to port 22, which is what someone installing
# just one of them wants.  Installing both means one has to move, and without
# this check the loser exits under KeepAlive forever with nothing in the log
# explaining why -- the most expensive possible way to find out.  A line naming
# the offending process turns it into a one-minute fix.
#
# iOS has no lsof and netstat there is unreliable, so this is a bind test:
# something already owning the port makes it fail.  The test connection is
# closed immediately so the real bind below is unaffected.
port_holder() {
    local p="$1" out=""
    out="$( (exec 3<>"/dev/tcp/0.0.0.0/$p") 2>/dev/null && ps -eo args 2>/dev/null )"
    exec 3>&- 2>/dev/null
    [ -n "$out" ] && echo "$out" | grep -iE "dropbear|sshd|sftp-server" | head -2
}

port_busy() {
    (exec 3<>"/dev/tcp/0.0.0.0/$PORT") 2>/dev/null
}
if port_busy; then
    exec 3>&- 2>/dev/null
    log "port $PORT is already in use -- not starting."
    log "holder: $(port_holder "$PORT" || echo 'unknown (no matching process name)')"
    log "this package and the other SSH package both default to 22; edit the"
    log "DROPBEAR_PORT value in /Library/LaunchDaemons/com.hesper.dropbear.plist"
    log "(a conffile, so your edit survives upgrades) and unload/load again."
    exit 1
fi
exec 3>&- 2>/dev/null

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
