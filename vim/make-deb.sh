#!/bin/bash
# Package the armv7 Vim build into a .deb for the APT repo.
#
# Follows ../wget/make-deb.sh and ../curl/make-deb.sh: the package installs
# under /var/mobile/tools so nothing in /usr is touched, and uninstalling is
# just `rm -rf /var/mobile/tools/{bin/vim*,share/vim}`.
#
# Usage:
#   ./vim/build.sh && ./vim/make-deb.sh
#
# Why the runtime ships inside the package (this is the whole point):
#   Vim locates its runtime through a compiled-in fall-back path plus $VIMRUNTIME
#   and the executable's own location.  Building with --prefix=/var/mobile/tools
#   bakes in
#       fall-back for $VIM: "/var/mobile/tools/share/vim"
#   so an install at that prefix just works: vim -es ... finds
#   share/vim/vim91 without $VIM or --cmd.  Verified on the device -- with the
#   tree present, `echo $VIMRUNTIME` prints /var/mobile/tools/share/vim/vim91
#   and `syntax on` over a C file sets b:current_syntax="c"; with the tree
#   absent vim still starts but filetype/syntax/indent are all dead.
#
#   The split is therefore: .deb contains bin/vim (+ ex/vi/view/vimdiff/...)
#   and the full share/vim/vim91 runtime.  Syntax, indent and ftplugin are kept
#   in full; only the doc/ tree is trimmed (see below).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
OUT="$root/out"
WORK="${WORK:-$root/tmp/vim-work}"
STAGE="${STAGE:-$WORK/stage}"
PREFIX="${PREFIX:-/var/mobile/tools}"

VIM_VERSION="${VIM_VERSION:-9.1.0000}"
VIM_RUNTIME_VER="${VIM_RUNTIME_VER:-vim91}"   # VIM_VERSION_NODOT, from src/version.h
DEBREV="${DEBREV:-1}"
MAINTAINER="${MAINTAINER:-Hesper <hesperup@users.noreply.github.com>}"

[ -d "$STAGE$PREFIX" ] || {
    echo "missing staging tree $STAGE$PREFIX (run vim/build.sh first)" >&2; exit 1; }
[ -x "$STAGE$PREFIX/bin/vim" ] || { echo "no vim in $STAGE$PREFIX/bin" >&2; exit 1; }

# Host ldid occasionally produces a binary the device kills with "Killed: 9"
# and no crash report; signing on the device always works.  Like
# curl/wget/make-deb.sh this signs twice: once here at build time (build.sh
# already did) and once on the copy that lands in the package.
sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    if command -v ldid >/dev/null 2>&1; then
        ldid -S "$dst" 2>/dev/null || true
    else
        echo "[!] ldid not found; the packaged binary will be unsigned" >&2
    fi
}

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/DEBIAN" "$w$PREFIX/bin" "$w$PREFIX/share/vim" \
         "$w/usr/share/doc/vim"

# ---------------------------------------------------------------- the runtime
# Copy the whole staged runtime, then trim only what is genuinely expendable.
cp -a "$STAGE$PREFIX/share/vim/." "$w$PREFIX/share/vim/"

# doc/ is 11 MB of the 31 MB runtime and is pure reference material -- nothing
# in syntax/indent/ftplugin/autoload reads it.  Keep tags (so :help can still
# find a topic name and jump) and drop the bulk text.  :help itself will only
# work for retained files, which is documented in the package description.
rt="$w$PREFIX/share/vim/$VIM_RUNTIME_VER"
if [ -d "$rt/doc" ]; then
    # Keep the small navigation files, drop the large *.txt bodies.
    find "$rt/doc" -name '*.txt' -size +40k -delete
    # help tags reference the deleted files; regenerate against what remains so
    # :help does not open a hole.  vim -es can rebuild its own tags file.
    if [ -x "$w$PREFIX/bin/vim" ]; then
        ( cd "$rt/doc" && rm -f tags && \
          "$w$PREFIX/bin/vim" -es -N -u NONE -i NONE \
              -c "helptags ." -c "qa!" >/dev/null 2>&1 ) || true
    fi
    [ -s "$rt/doc/tags" ] || echo "[!] note: doc/tags not regenerated; :help may be partial" >&2
fi

# ---------------------------------------------------------------- ownership / modes
# `cp -a` faithfully reproduces the build tree's modes, and that tree came from
# a umask-0002 shell: directories land as drwxrwxr-x and files as -rw-rw-r--,
# i.e. group-writable.  dpkg would install them that way, leaving a
# group-writable runtime that any member of group `mobile` could rewrite.  The
# staging tree is not authoritative about modes, so normalise the whole tree
# FIRST -- directories 0755, regular files 0644 -- and then let the binary step
# below re-mark the executables.  Order matters: doing this after the binary
# copy would silently strip the +x bit off vim itself (and a non-executable vim
# is a package that installs perfectly and cannot run).
find "$w" -type d -exec chmod 0755 {} +
find "$w" -type f -exec chmod 0644 {} +

# --------------------------------------------------------------- the binaries
# make install produced ex/rview/rvim/view/vimdiff as symlinks to vim, plus
# vimtutor (#!/bin/sh -- iOS has /bin/sh) and xxd, which build.sh verified is a
# real armv7 Mach-O.  Symlinks are preserved as-is; only the real file is signed.
for f in "$STAGE$PREFIX/bin"/*; do
    n="$(basename "$f")"
    if [ -L "$f" ]; then
        cp -a "$f" "$w$PREFIX/bin/$n"
    else
        sign "$f" "$w$PREFIX/bin/$n"
        chmod 0755 "$w$PREFIX/bin/$n"
    fi
done
# `vi`: upstream expects the OS to own that name, but on iOS nothing does and
# the brief asks for it.  build.sh stages it; make sure it survives.
ln -sf vim "$w$PREFIX/bin/vi"

# The runtime helpers under share/vim/.../tools are developer utilities rather
# than user commands, but upstream ships them executable; keep them that way so
# the package matches upstream's layout, and confirm the user-facing binaries
# really did come out executable.
find "$w$PREFIX/share/vim" -type f \( -name '*.pl' -o -name '*.py' -o -name '*.sh' \) \
    -exec chmod 0755 {} +
for n in vim vimtutor xxd; do
    [ -x "$w$PREFIX/bin/$n" ] || { echo "packaged bin/$n is not executable" >&2; exit 1; }
done
[ -L "$w$PREFIX/bin/vi" ] || { echo "packaged bin/vi symlink is missing" >&2; exit 1; }

# ---------------------------------------------------------------- packaging
cat > "$w/DEBIAN/control" <<CTRL
Package: vim
Name: Vim 9.1 (terminal)
Version: ${VIM_VERSION%%-*}-$DEBREV
Section: Editors
Priority: optional
Architecture: iphoneos-arm
Maintainer: $MAINTAINER
Homepage: https://www.vim.org/
Depiction: https://github.com/hesper-homelab-bot/ios-armv7-builder
Depends: firmware (>= 10.3)
Description: Vim 9.1 terminal editor for armv7 iOS 10+ (huge, +multi_byte)
 Terminal Vim $VIM_VERSION for armv7 iOS 10.x, built with --with-features=huge
 and +multi_byte, no GUI and no X11.  Links the device's own libSystem and
 /usr/lib/libncursesw.5.dylib, so no shared libraries are bundled.
 .
 Installs to $PREFIX: bin/{vim,vi,ex,view,vimdiff,rview,rvim,vimtutor,xxd}
 and the complete runtime under share/vim/$VIM_RUNTIME_VER.  Because vim is
 built with prefix=$PREFIX, it finds that runtime automatically -- no \$VIM,
 no \$VIMRUNTIME and no --cmd are needed.  Add $PREFIX/bin to your PATH.
 .
 syntax/, indent/ and ftplugin/ are complete (697/161/307 files).  doc/ is
 trimmed to keep the package small, so :help has only a partial offline
 manual; the tags file is regenerated for whatever is retained.
 .
 Working: terminal editing, multibyte/UTF-8, syntax highlighting, filetype
 detection, indenting, folding, spell checking, ctags/tags, vim9script, netrw,
 diff mode, persistent undo, terminfo-based termcap.  Not built: GUI, X11,
 clipboard providers, netbeans, cscope, channel/job (no +channel/+terminal),
 and all embedded interpreters (perl/python/ruby/lua/tcl) -- the device has
 none of them.  :terminal and :job are therefore unavailable; use tmux for
 multiple panes instead.
CTRL

cat > "$w/usr/share/doc/vim/copyright" <<CR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: vim
Source: https://github.com/vim/vim/archive/refs/tags/v$VIM_VERSION.tar.gz

Files: *
Copyright: 1991-2024 Bram Moolenaar and others
License: Vim
 This program is free software; you can redistribute it and/or modify
 it under the terms of the Vim License.  See ":help license".
 .
 I)  There are no restrictions on distributing unmodified copies of Vim
     except that they must include this license text.  You can also
     distribute unmodified parts of Vim, likewise unrestricted except that
     they must include this license text.  You are also allowed to include
     executables that (mostly) only do things from the Vim executable.
 .
 II) It is allowed to distribute a modified (or extended) version of Vim,
     including executables and/or source code, when the following four
     conditions are met:
 .
     1) This license text must be included unmodified.
 .
     2) The modified Vim must be distributed in one of the following five
        ways: whole source; whole source with a description of the
        modifications; an executable plus a description of how to obtain
        the source; an executable plus a written offer to obtain the source;
        or the executable alone if the source was distributed earlier.
 .
     3) If the modifications are included in the executable, they must be
        documented, and if third parties are not allowed to distribute the
        modified version, the modified Vim must be marked as such, and the
        executable must be marked as not being the original Vim.
 .
     4) If you distribute a modified Vim, the message "This Vim was not
        created by Bram Moolenaar" must be included in the executable.
 .
 III) The Vim license applies to all files in the distribution, unless
     stated otherwise.
 .
 IV) Charity: if you like Vim, please send a donation to a charity of your
     choice, or help people in Uganda.
 .
 The license text above is a summary of the terms; the authoritative text is
 the one that ships with Vim, "runtime/doc/uganda.txt" upstream (retained
 here in share/vim/$VIM_RUNTIME_VER/doc as far as the doc trim allows).
 .
 This package is a cross-compiled build for armv7 iOS 10.x.  No Apple SDK
 files are redistributed: the sysroot headers are original clean-room stubs or
 BSD-licensed musl headers, and the device libraries it links against at build
 time are present on the device itself.
CR

# The control/copyright files were written after the mode normalisation above,
# so they still carry the writer's umask (0664).  They are documentation; 0644
# is what every other package ships.
chmod 0644 "$w/DEBIAN/control" "$w/usr/share/doc/vim/copyright"

deb="$OUT/vim_${VIM_VERSION%%-*}-${DEBREV}_iphoneos-arm.deb"
mkdir -p "$OUT"
dpkg-deb --root-owner-group -Zgzip --build "$w" "$deb" >/dev/null
rm -rf "$w"; trap - EXIT

echo "==> $deb"
sha256sum "$deb"
echo
# `dpkg-deb -c | head` makes dpkg-deb die with "tar: stdout: write error" once
# head closes the pipe, which looks like a packaging failure and is not one.
# Capture the listing first, then slice it.
listing="$(dpkg-deb -c "$deb")"
echo "    contents:"
# sed -n '1,18p' rather than `... | head -18`: head exits early and the writer
# upstream of it gets SIGPIPE, which under `set -o pipefail` would fail the
# script even though the package is fine.
printf '%s\n' "$listing" | awk '{print "      " $1, $6}' | sed -n '1,18p'
echo "      ... ($(printf '%s\n' "$listing" | wc -l) entries)"
echo
echo "    install on device:"
echo "      scp $deb root@<device>:/var/mobile/ && dpkg -i /var/mobile/$(basename "$deb")"
echo "      # or: rm -rf /var/mobile/tools/share/vim && dpkg -i ..."
