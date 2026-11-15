#!/bin/bash
# make-deb.sh -- build ffmpeg deb for armv7 iOS 10.3.3
#
# Payload layout (class-dump4 pattern):
#   /var/mobile/tools/ffmpeg/ffmpeg    the real binary (stripped, signed)
#   /var/mobile/tools/ffmpeg/ffprobe
#   /var/mobile/tools/bin/ffmpeg       symlinks (login shells)
#   /var/mobile/tools/bin/ffprobe
# No Depends: fully static against libSystem + static openssl/zlib/
# libios-compat (see build.sh).  Binaries are stripped with llvm-strip-21
# before staging (GNU strip would corrupt Mach-O; ffmpeg static build is
# tens of MB with symbols).
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
UPSTREAM="$(sed -n 's/^#define FFMPEG_VERSION "\(.*\)"/\1/p' \
	"$ROOT/obj/libavutil/ffversion.h" 2>/dev/null | head -1)"
[ -n "$UPSTREAM" ] || { echo "cannot read FFMPEG_VERSION from obj/libavutil/ffversion.h" >&2; exit 1; }
VERSION="$UPSTREAM-1"
DEB="$REPO_OUT/ffmpeg_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/ffmpeg-stage"

[ -f "$ROOT/obj/ffmpeg" ] && [ -f "$ROOT/obj/ffprobe" ] || {
	echo "missing obj/ffmpeg obj/ffprobe -- run build.sh first" >&2
	exit 1
}
command -v llvm-strip-21 >/dev/null || { echo "missing llvm-strip-21" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE/var/mobile/tools/ffmpeg" \
         "$STAGE/var/mobile/tools/bin" \
         "$STAGE/DEBIAN"

for prog in ffmpeg ffprobe; do
	cp "$ROOT/obj/$prog" "$STAGE/var/mobile/tools/ffmpeg/$prog"
	llvm-strip-21 --strip-all "$STAGE/var/mobile/tools/ffmpeg/$prog"
	chmod 755 "$STAGE/var/mobile/tools/ffmpeg/$prog"
	ldid -S "$STAGE/var/mobile/tools/ffmpeg/$prog"
	ldid -e "$STAGE/var/mobile/tools/ffmpeg/$prog" >/dev/null
	ln -sf "/var/mobile/tools/ffmpeg/$prog" "$STAGE/var/mobile/tools/bin/$prog"
done

cat > "$STAGE/DEBIAN/control" <<EOF
Package: ffmpeg
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: FFmpeg $UPSTREAM (static, full built-in codecs) for iOS 10.3.3 armv7
 ffmpeg + ffprobe with all built-in encoders/decoders/muxers/demuxers/
 filters; network enabled (https via static OpenSSL 4.0.3, zlib via
 static 1.3.1).  SDK sysroot mode (real iPhoneOS10.3.sdk); ARM NEON asm
 via gas-preprocessor.  Successor of BigBoss com.nin9tyfour.ffmpeg 2.6.1.
Section: Multimedia
Priority: optional
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
for BIN in /var/mobile/tools/ffmpeg/ffmpeg /var/mobile/tools/ffmpeg/ffprobe; do
	[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
done
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
for L in /var/mobile/tools/bin/ffmpeg /var/mobile/tools/bin/ffprobe; do
	[ -L "$L" ] && rm -f "$L" || true
done
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -8
ls -lh "$DEB"
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
