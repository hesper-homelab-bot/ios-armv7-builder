#!/bin/bash
# make-deb.sh -- build python3 deb for armv7 iOS 10.3.3
#
# Payload layout:
#   /var/mobile/tools/python3/bin/python3         interpreter (signed)
#   /var/mobile/tools/python3/lib/python3.13/     stdlib + lib-dynload/*.so
#   /var/mobile/tools/bin/python3                 symlink
#
# Sources: interpreter from obj/python; stdlib from the CPython source Lib/
# tree; extension modules from obj/Modules/*.so (already signed here so the
# device's dlopen() accepts them).
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
SRC="${PYTHON_SRC:-$HOME/scratch/python3/src313}"
# OBJ is overridable because 3.13 and 3.14 share one repo directory; the
# 3.13 build tree lives in $HOME/scratch/python3/obj313, and build.sh still
# writes to $ROOT/obj.  Pass OBJ=... to package a specific tree.
OBJ="${PYTHON_OBJ:-$ROOT/obj}"
PYVER="3.13"
VERSION="3.13.18-1"
DEB="$REPO_OUT/python3_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/python3-stage"

[ -f "$OBJ/python" ] || { echo "missing $OBJ/python -- run build.sh first" >&2; exit 1; }
[ -d "$SRC/Lib" ] || { echo "missing $SRC/Lib" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE/var/mobile/tools/python3/bin" \
         "$STAGE/var/mobile/tools/python3/lib/python$PYVER/lib-dynload" \
         "$STAGE/var/mobile/tools/bin" \
         "$STAGE/DEBIAN"

# interpreter
cp "$OBJ/python" "$STAGE/var/mobile/tools/python3/bin/python3"
chmod 755 "$STAGE/var/mobile/tools/python3/bin/python3"
ldid -S "$STAGE/var/mobile/tools/python3/bin/python3"
ldid -e "$STAGE/var/mobile/tools/python3/bin/python3" >/dev/null

# stdlib (plain .py tree)
cp -r "$SRC/Lib/." "$STAGE/var/mobile/tools/python3/lib/python$PYVER/"
find "$STAGE/var/mobile/tools/python3/lib/python$PYVER" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

# extension modules: real files (they are symlinks in the build tree) + sign
if compgen -G "$OBJ/Modules/*.so" > /dev/null; then
	for so in "$OBJ"/Modules/*.so; do
		cp -L "$so" "$STAGE/var/mobile/tools/python3/lib/python$PYVER/lib-dynload/"
	done
	for so in "$STAGE/var/mobile/tools/python3/lib/python$PYVER/lib-dynload/"*.so; do
		chmod 755 "$so"
		ldid -S "$so" 2>/dev/null || true
	done
fi

ln -sf /var/mobile/tools/python3/bin/python3 "$STAGE/var/mobile/tools/bin/python3"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: python3
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: CPython 3.13.18 for iOS 10.3.3 armv7
 Full CPython built against the real iPhoneOS10.3.sdk, cross-compiled on
 Linux with cctools ld64.  Includes the standard library and 51 C extension
 modules (math, zlib, hashlib, sqlite3, _socket, ...).  NOTES: ssl/hashlib
 OpenSSL-backed modules are absent (OpenSSL static archive has armv7
 text-relocation issues in bundles); set PYTHONHOME if relocating.
Section: Development
Priority: optional
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN=/var/mobile/tools/python3/bin/python3
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
for so in /var/mobile/tools/python3/lib/python3.13/lib-dynload/*.so; do
	[ -f "$so" ] && ldid -e "$so" >/dev/null 2>&1
done
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ -L /var/mobile/tools/bin/python3 ] && rm -f /var/mobile/tools/bin/python3
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -6
ls -lh "$DEB"
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
