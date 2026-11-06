#!/bin/bash
# Atomically move the com.hesper.dropbear listener from 2222 to port 22,
# keeping 2222 as a verified fallback.  Run as root on the device.
#
# The script backs up the current plist, installs the new one, reloads the
# job, verifies that BOTH 22 and 2222 accept connections, and restores the
# backup if either check fails -- so a failed attempt cannot leave the device
# without the 2222 lifeline.
set -u

DST=/Library/LaunchDaemons/com.hesper.dropbear.plist
BAKDIR=/var/mobile/.local/etc/backup-dropbear-22
BAK="$BAKDIR/pre-2222.plist"
NEW="$BAKDIR/new-22.plist"
LABEL=com.hesper.dropbear

mkdir -p "$BAKDIR"
cp -p "$DST" "$BAK"

cat >"$NEW" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.hesper.dropbear</string>

	<!-- Runs as root so that the server can drop to the connecting user's
	     privileges after authentication, the same as /usr/sbin/sshd does. -->
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>/var/mobile/.local/bin/dropbear-daemon.sh</string>
	</array>

	<!-- Port 22 is the primary listener after the sshd cutover, and 2222 is
	     kept alongside it as a verified fallback so a regression on 22 cannot
	     cost remote access.  Dropbear listens on every -p it is given, so the
	     fallback is passed through DROPBEAR_EXTRA_ARGS as a second -p. -->
	<key>EnvironmentVariables</key>
	<dict>
		<key>DROPBEAR_PORT</key>
		<string>22</string>
		<key>DROPBEAR_EXTRA_ARGS</key>
		<string>-p 2222</string>
	</dict>

	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>

	<key>StandardErrorPath</key>
	<string>/var/mobile/.local/dropbear-daemon.err</string>
	<key>StandardOutPath</key>
	<string>/var/mobile/.local/dropbear-daemon.log</string>
</dict>
</plist>
EOF

chown root:wheel "$NEW"
chmod 644 "$NEW"

listen() {
    local port=$1
    (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null
}

reload() {
    launchctl unload "$DST" 2>/dev/null
    sleep 1
    launchctl load "$DST"
    sleep 2
}

echo "--- installing new plist (22 primary, 2222 fallback) ---"
cp "$NEW" "$DST"
chown root:wheel "$DST"
chmod 644 "$DST"
reload

ok22=0; ok2222=0
listen 22 && ok22=1
listen 2222 && ok2222=1

if [ "$ok22" = 1 ] && [ "$ok2222" = 1 ]; then
    echo "SWITCH OK: 22 and 2222 both listening"
else
    echo "SWITCH FAILED (ok22=$ok22 ok2222=$ok2222) -- reverting to 2222-only"
    cp "$BAK" "$DST"
    chown root:wheel "$DST"
    chmod 644 "$DST"
    reload
    if listen 2222; then
        echo "REVERT OK: 2222 restored"
    else
        echo "REVERT FAILED -- 2222 NOT LISTENING"
    fi
fi

echo "--- final listener ---"
ps aux | grep db-dropbear | grep -v grep
echo "--- port matrix ---"
for p in 22 2222 22222; do
    printf "port %-6s " "$p"
    if listen "$p"; then echo "LISTENING"; else echo "closed"; fi
done
echo "--- daemon log tail ---"
tail -5 /var/mobile/.local/dropbear-daemon.log 2>/dev/null
