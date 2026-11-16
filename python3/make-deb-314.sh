#!/bin/bash
# make-deb-314.sh -- CPython 3.14 deb for armv7 iOS 10.3.3
#
# Identical layout to the 3.13 package but under /var/mobile/tools/python314,
# so both interpreters can coexist.  Built from the 3.14 source tree with the
# ios-armv7 patches applied (see patches/).
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_OUT="$(cd "$ROOT/.." && pwd)/out"
SRC="${PYTHON_SRC:-$HOME/scratch/python3/src}"
OBJ="${PYTHON_OBJ:-$ROOT/obj}"
PYVER="3.14"
UPSTREAM="$(grep -m1 '^#define PY_VERSION' "$SRC/Include/patchlevel.h" | sed 's/.*"\(.*\)".*/\1/')"
VERSION="${UPSTREAM}-1"
DEB="$REPO_OUT/python314_${VERSION}_iphoneos-arm.deb"
STAGE="$REPO_OUT/python314-stage"
PREFIX=/var/mobile/tools/python314

[ -f "$OBJ/python" ] || { echo "missing $OBJ/python -- run build.sh first" >&2; exit 1; }
[ -d "$SRC/Lib" ] || { echo "missing $SRC/Lib" >&2; exit 1; }

rm -rf "$STAGE" "$DEB"
mkdir -p "$STAGE$PREFIX/bin" "$STAGE$PREFIX/lib/python$PYVER/lib-dynload" \
         "$STAGE/var/mobile/tools/bin" "$STAGE/DEBIAN"

cp "$OBJ/python" "$STAGE$PREFIX/bin/python3"
chmod 755 "$STAGE$PREFIX/bin/python3"
ldid -S "$STAGE$PREFIX/bin/python3"
ldid -e "$STAGE$PREFIX/bin/python3" >/dev/null

cp -r "$SRC/Lib/." "$STAGE$PREFIX/lib/python$PYVER/"
find "$STAGE$PREFIX/lib/python$PYVER" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

for so in "$OBJ"/Modules/*.so; do
    [ -e "$so" ] || continue
    cp -L "$so" "$STAGE$PREFIX/lib/python$PYVER/lib-dynload/"
done
for so in "$STAGE$PREFIX/lib/python$PYVER/lib-dynload/"*.so; do
    chmod 755 "$so"; ldid -S "$so" 2>/dev/null || true
done

ln -sf "$PREFIX/bin/python3" "$STAGE/var/mobile/tools/bin/python3.14"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: python314
Version: $VERSION
Architecture: iphoneos-arm
Maintainer: hesper <hesper-homelab-bot@users.noreply.github.com>
Description: CPython $UPSTREAM for iOS 10.3.3 armv7
 Full CPython with the standard library and 53 C extension modules
 (math, zlib, hashlib, sqlite3, ssl/OpenSSL 4.0.3, _socket, ...).
 TLS 1.3 verified on device.  Installs to /var/mobile/tools/python314 and
 coexists with python3 (3.13).  Needs PYTHONHOME=$PREFIX unless the prefix
 matches the build-time value.
Section: Development
Priority: optional
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
BIN=/var/mobile/tools/python314/bin/python3
[ -x "$BIN" ] && ldid -e "$BIN" >/dev/null 2>&1
for so in /var/mobile/tools/python314/lib/python3.14/lib-dynload/*.so; do
	[ -f "$so" ] && ldid -e "$so" >/dev/null 2>&1
done
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ -L /var/mobile/tools/bin/python3.14 ] && rm -f /var/mobile/tools/bin/python3.14
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/prerm"

dpkg-deb --root-owner-group -Zgzip --build "$STAGE" "$DEB" >/dev/null
echo "Built $DEB"
dpkg -I "$DEB" | head -6
ls -lh "$DEB"
echo "SHA256: $(sha256sum "$DEB" | cut -d' ' -f1)"
