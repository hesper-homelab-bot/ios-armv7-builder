#!/bin/sh
# nginx daemon wrapper for the iPad 4 (iOS 10.3.3, armv7).
#
# Installed as /var/mobile/.local/bin/nginx-daemon.sh and started by the
# LaunchDaemon com.hesper.nginx.  It exists for the same reason the dropbear
# wrapper does: launchd can only supervise a process that stays in the
# foreground, and nginx daemonises itself by default.
#
# The worker previously died on every start with
#     dyld: Symbol not found: _setproctitle
# because nginx's configure probe only *compiles* its test program, so the
# declaration in the sysroot overlay was enough to set
# NGX_HAVE_SETPROCTITLE=1 even though iOS libSystem does not export the
# symbol.  nginx/build.sh now unsets that macro, and the worker survives;
# this wrapper therefore only has to keep the master in the foreground.
set -u

PREFIX=/var/mobile/tools/nginx
NGINX="$PREFIX/bin/nginx"
CONF="$PREFIX/conf/nginx.conf"
PIDFILE="$PREFIX/logs/nginx.pid"

log() {
    echo "nginx-daemon: $*"
}

[ -x "$NGINX" ] || { log "missing $NGINX"; exit 1; }
[ -f "$CONF" ] || { log "missing $CONF"; exit 1; }

# nginx resolves logs/, tmp/, conf/ and share/ relative to its prefix; a
# dpkg upgrade or a stray rm can take the temp dirs with it, and nginx then
# refuses to start for a reason that looks unrelated.
mkdir -p "$PREFIX/logs" \
         "$PREFIX/tmp/client_body" "$PREFIX/tmp/proxy" \
         "$PREFIX/tmp/fastcgi" "$PREFIX/tmp/uwsgi" "$PREFIX/tmp/scgi"

# A stale pid file makes nginx exit with "invalid PID number"; it is only a
# number, so an unclean shutdown must not wedge the daemon.
[ -f "$PIDFILE" ] && ! kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null && rm -f "$PIDFILE"

log "starting nginx (master stays in foreground via -g 'daemon off;')"
# -g 'daemon off;' keeps the master in the foreground so launchd supervises
# it; KeepAlive then restarts nginx if it ever exits.
exec "$NGINX" -c "$CONF" -g 'daemon off;'
