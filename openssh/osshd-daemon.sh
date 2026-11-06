#!/bin/sh
# LaunchDaemon wrapper for the OpenSSH 10.6 sshd on the iPad 4.
#
# Started by /Library/LaunchDaemons/com.hesper.osshd.plist.  Deliberately a
# *third* SSH daemon, on its own port: dropbear owns 22 (and used to own 2222),
# the system OpenSSH 6.7p1 keeps 22222 under sshfix's protection, and this one
# runs the cross-built 10.6p2 so the new build can be exercised over real
# connections without touching either of the working paths.
#
# Why a wrapper rather than exec'ing ossh-sshd directly: the host keys are
# generated on first run and the .deb does not ship them, so without this a
# fresh install leaves sshd exiting immediately, which KeepAlive would retry
# forever and silently.  Mirrors dropbear/dropbear-daemon.sh on purpose -- same
# device, same failure mode, same fix.
#
# sshd must run as root (launchd's default): the build passes
# --with-privsep-user=_sshd, the same unprivileged user iOS reserves for sshd,
# so the pre-auth sandbox has an owner.  Without that configure flag sshd
# refuses to start at all with "Privilege separation user sshd does not exist".
set -u

TOOLS=/var/mobile/tools
KEYDIR=/var/mobile/ssh-openssh
SSHD="$TOOLS/ossh-sshd"
SSHKEYGEN="$TOOLS/ossh-ssh-keygen"
CONFIG=/var/mobile/ssh-openssh/sshd_config

log() { echo "osshd-daemon: $*"; }

# The port comes from sshd_config, not from here, so it is read out of it -- the
# only thing this wrapper needs to know in order to check the port is free.
PORT="$(sed -n 's/^[[:space:]]*Port[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p' "$CONFIG" 2>/dev/null | head -1)"
PORT="${PORT:-}"

# Same collision guard as dropbear's, for the same reason: both packages here
# default to 22, and the loser of a double install must say why it is not
# running instead of exiting silently under KeepAlive.  iOS has no lsof and
# netstat is unreliable, so this is a bind test.
if [ -n "$PORT" ]; then
    port_busy() { (exec 3<>"/dev/tcp/0.0.0.0/$PORT") 2>/dev/null; }
    if port_busy; then
        exec 3>&- 2>/dev/null
        log "port $PORT is already in use -- not starting."
        log "holder: $(ps -eo args 2>/dev/null | grep -iE 'dropbear|sshd|sftp-server' | head -2 | tr '\n' ' ')"
        log "this package and dropbear4 both default to 22; change the Port line in"
        log "$CONFIG (a conffile, so your edit survives upgrades) and load again."
        exit 1
    fi
    exec 3>&- 2>/dev/null
fi

[ -x "$SSHD" ]      || { log "missing $SSHD"; exit 1; }
[ -x "$SSHKEYGEN" ] || { log "missing $SSHKEYGEN"; exit 1; }
[ -f "$CONFIG" ]    || { log "missing $CONFIG"; exit 1; }

# ed25519 first, rsa kept alongside it: some very old *client* still on the
# other end of a connection cannot do ed25519, and ssh-rsa costs nothing here.
if [ ! -s "$KEYDIR/ssh_host_ed25519_key" ]; then
    log "generating ed25519 host key"
    mkdir -p "$KEYDIR"
    "$SSHKEYGEN" -q -t ed25519 -N '' -f "$KEYDIR/ssh_host_ed25519_key" \
        >/dev/null 2>&1 || log "ed25519 keygen failed"
fi

if [ ! -s "$KEYDIR/ssh_host_rsa_key" ]; then
    log "generating rsa host key"
    mkdir -p "$KEYDIR"
    "$SSHKEYGEN" -q -t rsa -b 2048 -N '' -f "$KEYDIR/ssh_host_rsa_key" \
        >/dev/null 2>&1 || log "rsa keygen failed"
fi

# The private keys must not be readable by anyone but the daemon, or sshd's
# own StrictModes refuses them.
chmod 600 "$KEYDIR/ssh_host_ed25519_key" "$KEYDIR/ssh_host_rsa_key" 2>/dev/null

[ -s "$KEYDIR/ssh_host_ed25519_key" ] || { log "no ed25519 key"; exit 1; }

# -F would tell sshd to stay in the foreground *and* skip the privilege-drop
# path it normally uses; -D is the right flag here, and -e keeps the log on
# stderr so it lands in the plist's StandardErrorPath.
exec "$SSHD" -D -e -f "$CONFIG"
