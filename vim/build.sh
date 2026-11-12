#!/bin/bash
# ============================================================================
#  Build terminal Vim 9.1 for a jailbroken 32-bit iOS device (iPad 4, armv7,
#  iOS 10.3.3) on a Linux host -- no Xcode, no iOS SDK, no macOS.
#
#  Result: a Mach-O armv7 `vim` (LC_VERSION_MIN_IPHONEOS 10.3) that links the
#  device's own libSystem and libncursesw.5.dylib, plus a fully populated
#  runtime tree under /var/mobile/tools/share/vim/vim91.
#
#  Usage:
#     ./vim/build.sh                       # Vim 9.1.0000 (default)
#     VIM_VERSION=9.1.0000 ./build.sh
#     DEVICE=ipad ./build.sh               # ssh host, only needed to re-pull
#                                          # ncurses headers if the sysroot
#                                          # does not have them yet
#
#  Needed in the environment (same contract as ../tmux/build.sh, ../wget/build.sh):
#     IOS_LD64      cctools-port's x86_64-apple-darwin*-ld
#     LD64_LIBS     LD_LIBRARY_PATH for that ld64 (libdispatch, tapi)
#     LD64          accepted as an alias for IOS_LD64
#
#  Deliberately does NOT run `make install` without STRIP override -- see
#  WALL 2 below.
# ============================================================================
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

# --------------------------------------------------------------- configuration
VIM_VERSION="${VIM_VERSION:-9.1.0000}"
ARCH="${ARCH:-armv7}"
TARGET_IOS="${TARGET_IOS:-10.3}"
PREFIX="${PREFIX:-/var/mobile/tools}"
DEVICE="${DEVICE:-ipad}"          # ssh host; used only for the ncurses headers

WORK="${WORK:-$root/tmp/vim-work}"
OUT="${OUT:-$root/out}"
SRCDIR="${VIM_SRC:-$HOME/ios-tool/vim-src}"
SRC="$SRCDIR/vim-$VIM_VERSION"
STAGE="$WORK/stage"
NCDYLIB="${NCDYLIB:-$HOME/ios-tool/device-libs/libncursesw.5.dylib}"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ preflight
preflight() {
    say "checking the host toolchain"
    export IOS_SYSROOT="${IOS_SYSROOT:-$root/tmp/sysroot}"
    export IOS_STUBDIR="${IOS_STUBDIR:-$HOME/ios-tool}"
    export IOS_LD64="${IOS_LD64:-${LD64:-}}"
    [ -n "$IOS_LD64" ] && [ -x "$IOS_LD64" ] \
        || die "set IOS_LD64 (or LD64) to cctools-port's ld64"
    export LD_LIBRARY_PATH="${LD64_LIBS:-}:${LD_LIBRARY_PATH:-}"
    [ -d "$IOS_SYSROOT/usr/include" ] || die "sysroot missing: $IOS_SYSROOT"
    command -v curl >/dev/null || die "curl not found"

    # `strip` is never called by this script with the host's tool, but the
    # Makefile's install target would love to.  Make sure a Mach-O-capable
    # stripper is around (WALL 2).
    LLVM_STRIP="${LLVM_STRIP:-}"
    if [ -z "$LLVM_STRIP" ]; then
        for c in llvm-strip llvm-strip-21 llvm-strip-20 llvm-strip-19 \
                 /usr/lib/llvm-*/bin/llvm-strip; do
            command -v "$c" >/dev/null 2>&1 && LLVM_STRIP="$c" && break
            [ -x "$c" ] && LLVM_STRIP="$c" && break
        done
    fi
    [ -n "$LLVM_STRIP" ] || die "llvm-strip not found (needed instead of GNU strip)"
    export LLVM_STRIP
    echo "    clang      : $(clang --version | head -1)"
    echo "    llvm-strip : $LLVM_STRIP"
    echo "    ld64       : $IOS_LD64"
    echo "    sysroot    : $IOS_SYSROOT"
    echo "    target     : $ARCH-apple-ios$TARGET_IOS"
}

# --------------------------------------------------------------------- sources
fetch_sources() {
    say "fetching Vim $VIM_VERSION"
    mkdir -p "$SRCDIR"
    # Vim has no "releases" tarball for patchlevels; the git tag archives on
    # GitHub are the canonical source for v9.1.0000 (the FTP site only carries
    # the unpatched v9.1.0000 for the 9.1 line and per-patch deltas after that).
    local tar="$SRCDIR/vim-$VIM_VERSION.tar.gz"
    if [ ! -s "$tar" ]; then
        curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$tar.part" \
            "https://github.com/vim/vim/archive/refs/tags/v$VIM_VERSION.tar.gz" \
            || die "could not download Vim $VIM_VERSION"
        mv "$tar.part" "$tar"
    fi
    [ -d "$SRC" ] || tar xzf "$tar" -C "$SRCDIR"
    [ -d "$SRC" ] || die "source dir not found: $SRC"
    echo "    $SRC"
}

# -------------------------------------------------------------- ncurses headers
# WALL 1 (part a): the sysroot is musl-derived and has NO ncurses headers.  Vim
# cannot build without <ncurses.h> / <term.h>, and the device's ncurses is
# ncurses 5.7 with the wide-character API in /usr/include/ncursesw.  Same
# approach as ../tmux/build.sh: pull them off the device once.
ensure_ncurses_headers() {
    local inc="$IOS_SYSROOT/usr/include"
    if [ -f "$inc/ncurses.h" ] && [ -f "$inc/term.h" ] && [ -d "$inc/ncursesw" ]; then
        say "ncurses headers already in the sysroot"
        echo "    $inc/ncurses.h"
        return 0
    fi
    say "pulling ncurses headers off the device ($DEVICE)"
    command -v ssh >/dev/null || die "ssh not found and headers are missing"
    local tmp; tmp="$(mktemp)"
    ssh -o BatchMode=yes "$DEVICE" \
        'cd /usr/include && tar cf - ncurses.h curses.h term.h ncurses_dll.h \
            nc_tparm.h termcap.h unctrl.h eti.h panel.h menu.h form.h ncursesw' \
        > "$tmp" || die "could not read ncurses headers from $DEVICE"
    tar xf "$tmp" -C "$inc" || die "could not unpack ncurses headers"
    rm -f "$tmp"
    [ -f "$inc/ncurses.h" ] || die "ncurses.h still missing after the pull"
    echo "    installed into $inc"
}

# ---------------------------------------------------- device libncursesw.5.dylib
ensure_ncurses_dylib() {
    say "device ncurses dylib"
    if [ ! -s "$NCDYLIB" ]; then
        mkdir -p "$(dirname "$NCDYLIB")"
        ssh -o BatchMode=yes "$DEVICE" 'cat /usr/lib/libncursesw.5.dylib' \
            > "$NCDYLIB" || die "could not read libncursesw from $DEVICE"
    fi
    [ -s "$NCDYLIB" ] || die "empty libncursesw at $NCDYLIB"
    echo "    $NCDYLIB ($(wc -c < "$NCDYLIB") bytes)"
}

# ------------------------------------------------------------------- configure
export_cc() {
    export CC="$root/tools/cc-wrapper.sh"
    export AR="$root/tools/darwin-ar"
    export RANLIB="$root/tools/darwin-ranlib"
    export LLVM_AR="${LLVM_AR:-llvm-ar-21}"

    # WALL 3: the ncurses *link*.  cc-wrapper.sh drops -lncursesw on the floor
    # (it is in the "everything lives in libSystem on Darwin" list) -- which is
    # right for -lc/-lm but wrong here, because libncursesw is emphatically NOT
    # in libSystem.  The wrapper's IOS_DYLIBS variable is the escape hatch: it
    # appends raw link objects, and it classifies *.dylib as a link input and
    # hands the path to ld64.  That is what makes ld64 record an
    # LC_LOAD_DYLIB for /usr/lib/libncursesw.5.dylib and bind the 10 termcap
    # symbols it needs (tgetent/tgetstr/tgoto/tputs/UP/BC/PC/ospeed/...)
    # two-level against it instead of leaving them to a dynamic_lookup.
    export IOS_DYLIBS="$NCDYLIB"

    # Vim's own probe corrections.  See ios-config.site for the full story.
    export CONFIG_SITE="$here/ios-config.site"

    export CPPFLAGS="-I$IOS_SYSROOT/usr/include -I$IOS_SYSROOT/usr/include/ncursesw"
    export CFLAGS="-O2 $CPPFLAGS"
}

configure_vim() {
    say "configuring Vim $VIM_VERSION for $ARCH-apple-ios$TARGET_IOS"
    cd "$SRC"
    make distclean >/dev/null 2>&1 || true
    cd src

    # WALL 1 (part b -- the one that actually bit):
    #   os_unix.c guards the *include* of <sys/sysctl.h> with
    #       #if defined(HAVE_SYS_SYSCTL_H) && defined(HAVE_SYSCTL)
    #   but guards its *use* with `#ifdef HAVE_SYSCTL` alone.  Forcing
    #   ac_cv_header_sys_sysctl_h=no (the intuitive move: "a musl sysroot has no
    #   sysctl.h") therefore leaves the use block compiled with no declaration:
    #       os_unix.c:577:11: error: use of undeclared identifier 'CTL_HW'
    #       os_unix.c:583:6: error: call to undeclared function 'sysctl'
    #   The sysroot in fact ships a hand-adapted Darwin sys/sysctl.h copied
    #   field-for-field from xnu-3789.70.16 -- the exact kernel on this device --
    #   with CTL_HW, HW_USERMEM and sysctl() all present.  ios-config.site says
    #   yes to both, and the two guards agree.
    #
    # Everything else here matches the brief: huge feature set, multibyte,
    # no GUI/X11, no NLS, no netbeans, no interpreters (the device has only
    # node4 -- no python/perl/lua/ruby/tcl at all, so interpreter support would
    # be dead weight that cannot even be loaded).
    ./configure \
        --host="$ARCH-apple-darwin" \
        --build="$(cc -dumpmachine)" \
        --prefix="$PREFIX" \
        --with-features=huge \
        --enable-multibyte \
        --with-tlib=ncursesw \
        --disable-gui --without-x \
        --disable-nls --disable-netbeans \
        --disable-canberra --disable-gpm --disable-sysmouse \
        --with-compiledby="hesper (armv7 iOS $TARGET_IOS)" \
        --disable-pythoninterp --disable-python3interp \
        --disable-perlinterp --disable-luainterp \
        --disable-rubyinterp --disable-tclinterp \
        --disable-cscope \
        --disable-channel --disable-terminal \
        > "$WORK/configure.log" 2>&1 \
        || { tail -30 "$WORK/configure.log" >&2; die "configure failed"; }

    [ -f auto/config.h ] || die "configure did not produce auto/config.h"

    # The two sysctl answers MUST agree, or the build dies in os_unix.c.  This
    # is the cheapest possible check for the mistake described above.
    local have_fn have_hdr
    have_fn=$(grep -c '^#define HAVE_SYSCTL 1' auto/config.h || true)
    have_hdr=$(grep -c '^#define HAVE_SYS_SYSCTL_H 1' auto/config.h || true)
    if [ "$have_fn" != "$have_hdr" ]; then
        die "sysctl guards disagree (HAVE_SYSCTL=$have_fn HAVE_SYS_SYSCTL_H=$have_hdr); see ios-config.site"
    fi

    echo "    configure OK (HAVE_SYSCTL=$have_fn HAVE_SYS_SYSCTL_H=$have_hdr)"
    grep -E '^#define (TERMINFO|FEAT_HUGE|BROKEN_TOUPPER|STAT_IGNORES_SLASH)' auto/config.h \
        | sed 's/^/    /' || true
}

# ------------------------------------------------------------------- compile
build_vim() {
    say "compiling"
    cd "$SRC/src"
    # WALL 4: `make` needs host tools as well as the cross compiler.
    #   * the top-level Makefile runs the *host* `cc` for a couple of
    #     configure-time helpers, and it invokes `install-sh`, `sed`, `awk`
    #     and `sh` from the host.  That is correct and expected: they generate
    #     sources (auto/pathdef.c) rather than target objects.
    #   * What is NOT acceptable is letting the host's `strip` or `ar` touch
    #     target files.  AR/RANLIB are pinned to the Darwin-capable wrappers
    #     above; STRIP is pinned at install time (WALL 2).
    #   * `make` also runs ./link.sh, which re-links with libraries removed to
    #     see what is redundant.  Under -undefined dynamic_lookup every variant
    #     links, so link.sh settles on the unmodified command.  Harmless, but
    #     it means an "OK" from link.sh proves nothing about symbol availability
    #     -- which is exactly why the undefined-symbol audit below exists.
    make -j"$(nproc)" > "$WORK/make.log" 2>&1 \
        || { grep -n -E 'error:|Error [0-9]' "$WORK/make.log" | head -20 >&2; die "make failed"; }
    [ -x vim ] || die "no vim binary produced"

    echo "    built: $(stat -c%s vim) bytes"
}

# WALL 5: -undefined dynamic_lookup means the link "succeeds" no matter what is
# missing.  A binary that links cleanly can still abort in dyld on the device
# with "Symbol not found".  So classify every undefined symbol: each one must be
# either exported by the device's libncursesw (the dylib we link) or a symbol we
# expect libSystem to provide.  Anything else is a porting bug to chase down on
# the host rather than on the device.
audit_symbols() {
    say "auditing undefined symbols"
    cd "$SRC/src"
    local undef="$WORK/undefined.txt" ncsyms="$WORK/ncurses-symbols.txt"
    llvm-nm-21 -u vim 2>/dev/null | awk '{print $NF}' | LC_ALL=C sort -u > "$undef"
    llvm-nm-21 -gU "$NCDYLIB" 2>/dev/null | awk '{print $NF}' | LC_ALL=C sort -u > "$ncsyms"
    local nc_hits
    nc_hits=$(comm -12 "$undef" "$ncsyms" | wc -l)
    comm -23 "$undef" "$ncsyms" > "$WORK/libsystem-symbols.txt"
    local total rest
    total=$(wc -l < "$undef"); rest=$(wc -l < "$WORK/libsystem-symbols.txt")
    echo "    undefined total        : $total"
    echo "    from libncursesw.5     : $nc_hits"
    echo "    expected from libSystem: $rest"
    # The ncurses half is the interesting one: those are the symbols that only
    # resolve because IOS_DYLIBS put the dylib on the link line.  If this drops
    # to 0, IOS_DYLIBS silently stopped working (e.g. -lncursesw was left to
    # cc-wrapper, which discards it) and every termcap call would become a
    # dynamic_lookup that dyld resolves against libSystem -- where it does not
    # exist.
    [ "$nc_hits" -gt 0 ] \
        || die "no ncurses symbols resolved from the device dylib -- IOS_DYLIBS is not reaching ld64"
    # iostream/ObjC drift from the host would show up here as symbols that are
    # neither: catch the obvious GNU-isms that the musl headers declare but iOS
    # never exported.
    local bad
    bad=$(grep -E '^_(memrchr|strchrnul|mempcpy|stpcpy|iconv_open|vfork|__secure_getenv|eaccess|faccessat)$' \
              "$WORK/libsystem-symbols.txt" || true)
    [ -z "$bad" ] || die "symbols iOS does not export leaked into the link: $(echo "$bad" | tr '\n' ' ')"
    echo "    no known-absent GNU-isms in the libSystem set"
}

# ------------------------------------------------------------------- install
stage_install() {
    say "make install into staging ($STAGE)"
    rm -rf "$STAGE"
    cd "$SRC/src"
    # WALL 2: the Makefile ships `#STRIP = strip` *commented out*, so an
    # unqualified `make install` runs the host's /usr/bin/strip -- which on this
    # box is x86_64-linux-gnu-strip -- over an armv7 Mach-O.  GNU strip does not
    # recognise Mach-O; depending on the build it either errors out or, worse,
    # mangles the file.  llvm-strip speaks Mach-O and is ABI-correct for armv7.
    # (Alternative: STRIP=/bin/true keeps the symbols; that is also fine, just
    # a larger binary.  llvm-strip is chosen so the packaged vim is small.)
    make install DESTDIR="$STAGE" STRIP="$LLVM_STRIP" \
        > "$WORK/install.log" 2>&1 \
        || { tail -20 "$WORK/install.log" >&2; die "make install failed"; }

    local b="$STAGE$PREFIX/bin"
    [ -x "$b/vim" ] || die "no vim in the staging tree"
    file "$b/vim" | grep -q 'Mach-O armv7' \
        || die "staged vim is not Mach-O armv7 -- did a host tool touch it?"

    # WALL 6: helper scripts.  This device has /bin/sh, /bin/bash, awk and sed,
    # but NO perl, python, ruby, lua, tclsh or node.  So every script in the
    # package needs checking, in two tiers:
    #
    #   * $PREFIX/bin/* -- these are what a user actually runs.  vimtutor is
    #     #!/bin/sh, which is fine.  A #!/usr/bin/perl helper here would be
    #     dead on arrival, so it is a hard failure.
    #
    #   * $PREFIX/share/vim/vim91/tools/* -- upstream's optional developer
    #     utilities (demoserver.py, effm_filter.pl, pltags.pl, shtags.pl,
    #     vim2html.pl).  None of them is referenced by any .vim runtime file
    #     (checked: no plugin/, autoload/ or ftplugin/ script mentions them) and
    #     vim never shells out to them.  They ship as part of the upstream
    #     runtime, so they stay, but only as an informational note -- failing
    #     the build over them would be wrong.
    #
    # Reading a Mach-O with head(1) emits "ignored null byte" noise, so only
    # text-looking files are examined.
    local f first bad=0
    while IFS= read -r f; do
        case "$f" in
            # only inspect what looks like a script
            *.pl|*.py|*.sh|*.csh|vimtutor|*.awk) ;;
            *) continue;;
        esac
        first=$(head -c 120 "$f" 2>/dev/null | head -1)
        case "$first" in
            '#!'*) case "$first" in
                    *perl*|*python*|*ruby*|*lua*|*tcl*|*node*)
                        case "$f" in
                            "$STAGE$PREFIX/bin/"*)
                                warn "bin/ helper needs an interpreter iOS lacks: $f ($first)"
                                bad=1;;
                            *)
                                echo "    note: optional runtime tool needs a missing interpreter (kept anyway): ${f#$STAGE$PREFIX/}";;
                        esac;;
                  esac;;
        esac
    done < <(find "$STAGE$PREFIX" -type f -perm -u+x 2>/dev/null)
    [ "$bad" -eq 0 ] || die "a packaged bin/ helper needs an interpreter the device does not have"

    # `vi` compatibility symlink.  Vim's install target creates ex/view/rview/
    # rvim/vimdiff but NOT vi, because upstream expects the OS to own that name.
    # On iOS nothing else owns it, and the brief asks for it, so add it here.
    ln -sf vim "$b/vi"

    echo "    runtime : $(du -sh "$STAGE$PREFIX/share/vim" | cut -f1) under $PREFIX/share/vim"
    echo "    syntax/indent/ftplugin: $(ls "$STAGE$PREFIX/share/vim/vim91/syntax" | wc -l)/$(ls "$STAGE$PREFIX/share/vim/vim91/indent" | wc -l)/$(ls "$STAGE$PREFIX/share/vim/vim91/ftplugin" | wc -l) files"
    echo "    bin     : $(ls "$b" | tr '\n' ' ')"
}

# Why the runtime must be packaged at all, and why the prefix matters:
# Vim finds its runtime by compiling in a single fall-back path and otherwise
# walking up from $VIMRUNTIME / the executable's own directory.  Building with
# --prefix=/var/mobile/tools bakes in
#     fall-back for $VIM: "/var/mobile/tools/share/vim"
# so a vim installed to that prefix finds share/vim/vim91 with no $VIM,
# $VIMRUNTIME or --cmd needed.  Verified on the device: with the tree in place
# `echo $VIMRUNTIME` prints /var/mobile/tools/share/vim/vim91 and `syntax on`
# over a .c file sets b:current_syntax to "c".  Without the runtime vim still
# starts (it is not crashy), but filetype/syntax/indent are all dead.

sign() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    if command -v ldid >/dev/null 2>&1; then
        ldid -S "$dst" 2>/dev/null || true
    else
        warn "ldid not found; the binary is unsigned (make-deb.sh will still try)"
    fi
}

main() {
    mkdir -p "$WORK" "$OUT"
    preflight
    fetch_sources
    ensure_ncurses_headers
    ensure_ncurses_dylib
    export_cc
    configure_vim
    build_vim
    audit_symbols
    stage_install

    say "publishing the binary"
    mkdir -p "$OUT"
    sign "$SRC/src/vim" "$OUT/vim-$VIM_VERSION-armv7"
    chmod 0755 "$OUT/vim-$VIM_VERSION-armv7"
    file "$OUT/vim-$VIM_VERSION-armv7" | sed 's/^/    /'

    cat <<EOF

    binary  : $OUT/vim-$VIM_VERSION-armv7
    staging : $STAGE   (full runtime tree, prefix $PREFIX)
    logs    : $WORK/{configure,make,install}.log
    undefined-symbol audit: $WORK/{undefined,ncurses-symbols,libsystem-symbols}.txt

    Next: ./vim/make-deb.sh    (packages the staging tree into a .deb)
EOF
}

main "$@"
