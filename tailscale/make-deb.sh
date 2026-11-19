#!/bin/bash
# Package the armv7 tailscale build into a .deb for the APT repo.
#
# Follows ../nginx/make-deb.sh conventions: everything under
# /var/mobile/tools/tailscale, double signing (host ldid + device ldid in
# postinst), and NO auto-start -- the LaunchDaemon ships with
# <Disabled><true/> because the device owner keeps services off to save
# power (the nginx lesson).  Starting it is explicit:
#
#     launchctl load -w /Library/LaunchDaemons/com.hesper.tailscale.plist
#
# or, without launchd, run the wrapper directly as the mobile user.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
TS_VERSION="${TS_VERSION:-$(tr -d '[:space:]' < "$HOME/scratch/tailscale/src/VERSION.txt")}"
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"
PREFIX="/var/mobile/tools/tailscale"

CLI_BIN="$OUT/tailscale-$TS_VERSION-armv7"
D_BIN="$OUT/tailscaled-$TS_VERSION-armv7"
[ -f "$CLI_BIN" ] && [ -f "$D_BIN" ] || {
    echo "missing $CLI_BIN / $D_BIN (run tailscale/build.sh)" >&2; exit 1;
}

sign() { cp "$1" "$2" && ldid -S "$2" 2>/dev/null || true; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" \
         "$w$PREFIX/bin" \
         "$w/var/mobile/.local/bin" \
         "$w/Library/LaunchDaemons" \
         "$w/usr/share/doc/tailscale4"

cat > "$w/DEBIAN/control" <<CTRL
Package: tailscale4
Name: tailscale $TS_VERSION
Version: $TS_VERSION-$DEBREV
Section: Networking
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://tailscale.com/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: tailscale $TS_VERSION for armv7 iOS 10+ (Go 1.27.2 darwin/arm port)
 tailscale CLI + daemon cross-compiled with the revived Go 1.27.2
 darwin/arm toolchain.  iOS 10 has no /dev/tun, so the daemon runs with
 --tun=userspace-networking (gvisor netstack; SOCKS5/HTTP loopback
 proxies on :1055/:1056).
 .
 The LaunchDaemon ships DISABLED (device keeps services off to save
 power).  Start it explicitly:
   launchctl load -w /Library/LaunchDaemons/com.hesper.tailscale.plist
 Then log in (prints an auth URL):
   /var/mobile/tools/tailscale/bin/tailscale \\
     --socket=/var/mobile/tools/tailscale/tailscaled.sock login
CTRL

cat > "$w/DEBIAN/postinst" <<'POST'
#!/bin/sh
# Runs as root.  Signs with the device's own ldid (host signatures
# occasionally get Killed: 9 with no crash report), fixes ownership, and
# does NOT load the daemon: the plist ships Disabled by design.
set -e
PREFIX=/var/mobile/tools/tailscale
if command -v ldid >/dev/null 2>&1; then
    ldid -S "$PREFIX/bin/tailscale" 2>/dev/null || true
    ldid -S "$PREFIX/bin/tailscaled" 2>/dev/null || true
fi
mkdir -p "$PREFIX"
chown -R mobile:mobile "$PREFIX" 2>/dev/null || true
chmod 0755 "$PREFIX/bin/tailscale" "$PREFIX/bin/tailscaled" 2>/dev/null || true
chown mobile:mobile /var/mobile/.local/bin/tailscale-daemon.sh 2>/dev/null || true
chmod 0755 /var/mobile/.local/bin/tailscale-daemon.sh 2>/dev/null || true
chown root:wheel /Library/LaunchDaemons/com.hesper.tailscale.plist 2>/dev/null || true
chmod 0644 /Library/LaunchDaemons/com.hesper.tailscale.plist 2>/dev/null || true
exit 0
POST
chmod 0755 "$w/DEBIAN/postinst"

cat > "$w/DEBIAN/prerm" <<'PRE'
#!/bin/sh
# Stop the daemon before files disappear (best effort, never fails).
set -e
if command -v launchctl >/dev/null 2>&1; then
    launchctl remove com.hesper.tailscale >/dev/null 2>&1 || true
fi
exit 0
PRE
chmod 0755 "$w/DEBIAN/prerm"

sign "$CLI_BIN" "$w$PREFIX/bin/tailscale"
sign "$D_BIN"  "$w$PREFIX/bin/tailscaled"
chmod 0755 "$w$PREFIX/bin/tailscale" "$w$PREFIX/bin/tailscaled"

# Foreground wrapper for launchd supervision (same pattern as nginx).
cat > "$w/var/mobile/.local/bin/tailscale-daemon.sh" <<'DAE'
#!/bin/sh
# tailscaled wrapper: launchd can only supervise a foreground process.
PREFIX=/var/mobile/tools/tailscale
mkdir -p "$PREFIX"
exec "$PREFIX/bin/tailscaled" \
    --tun=userspace-networking \
    --statedir="$PREFIX" \
    --socks5-server=localhost:1055 \
    --outbound-http-proxy-listen=localhost:1056 \
    --socket="$PREFIX/tailscaled.sock" >>"$PREFIX/daemon.log" 2>&1
DAE
chmod 0755 "$w/var/mobile/.local/bin/tailscale-daemon.sh"

cat > "$w/Library/LaunchDaemons/com.hesper.tailscale.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.hesper.tailscale</string>
	<!-- Ships disabled: the device owner starts services explicitly. -->
	<key>Disabled</key>
	<true/>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>/var/mobile/.local/bin/tailscale-daemon.sh</string>
	</array>
	<key>UserName</key>
	<string>mobile</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>/var/mobile/tools/tailscale/daemon.log</string>
	<key>StandardErrorPath</key>
	<string>/var/mobile/tools/tailscale/daemon.log</string>
</dict>
</plist>
PLIST
chmod 0644 "$w/Library/LaunchDaemons/com.hesper.tailscale.plist"

cat > "$w/usr/share/doc/tailscale4/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: tailscale
Source: https://github.com/tailscale/tailscale

Files: *
Copyright: 2019-2026 Tailscale Inc. & AUTHORS
License: BSD-3-Clause

Files: debian/*
Copyright: 2026 Hesper <hesperup@users.noreply.github.com>
License: BSD-3-Clause

Cross-compiled for armv7 iOS 10.x with a revived Go 1.27.2 darwin/arm
toolchain.  No Apple SDK files are redistributed.
CR

dpkg-deb --root-owner-group -Zgzip --build "$w" \
    "$OUT/tailscale4_${TS_VERSION}-${DEBREV}_iphoneos-arm.deb" >/dev/null
rm -rf "$w"; trap - EXIT

deb="$OUT/tailscale4_${TS_VERSION}-${DEBREV}_iphoneos-arm.deb"
echo "==> $deb"
sha256sum "$deb"
echo "    install (root):"
echo "      scp $deb <device>:/var/mobile/"
echo "      ssh root@<device> dpkg -i /var/mobile/$(basename "$deb")"
