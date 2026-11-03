#!/bin/bash
# Idempotent source and Makefile fixups.
#
# With the corrected sysroot headers (see sysroot-overlay/) the upstream tmux
# code builds and runs as-is.  What remains here:
#
#   1. autoconf probes that always "succeed" because our linker tolerates
#      undefined symbols (they resolve from the device at runtime).  Anything
#      iOS 10 does not actually provide must be disabled by hand and replaced
#      with tmux's own bundled implementation, or the process dies at load
#      time with "DYLD, Symbol not found" - closefrom() being the nastiest
#      since it is called in the forked child of every new pane.
#   2. the event backend choice: kqueue must go, see the README.
#   3. libevent's bundled fallback clashes with the sysroot's declarations.

# ------------------------------------------------------------------ libevent
fix_libevent_sources() {
    local d="$1"
    # The sysroot declares strtok_r/strsep; libevent's bundled fallbacks then
    # clash ("static declaration follows non-static declaration").
    sed -i 's/\bstrtok_r\b/evdns_strtok_r/g' "$d/evdns.c"
    sed -i 's/\bstrsep\b/evhttp_strsep/g'    "$d/http.c"
}

# ---------------------------------------------------------------------- tmux
fix_tmux_sources() {
    local d="$1"
    # sys/sysctl.h does not exist in the cross sysroot.  The only code needing
    # it is compiled out via HAVE_PROC_PIDINFO, so drop the include.
    sed -i 's|^#include <sys/sysctl.h>$|/* sys/sysctl.h unavailable in cross sysroot */|' \
        "$d/osdep-darwin.c"

    # Force the poll backend.  Upstream sets EVENT_NOKQUEUE *and* EVENT_NOPOLL
    # (-> select) on Darwin.  On iOS 10:
    #   - kqueue breaks the moment a pty master joins the event base: a
    #     minimal libevent program on the device stops reporting the listen
    #     socket entirely once a tty fd is registered (accept never fires).
    #   - poll passed every check, including pty handling.
    # Keep EVENT_NOPOLL and remove only the kqueue disable so libevent
    # chooses poll.
    sed -i '/setenv("EVENT_NOKQUEUE", "1", 1);/d' "$d/osdep-darwin.c"
}

fix_tmux_makefile() {
    local d="$1" ncdylib="$2" mf="$1/Makefile"
    # compat/ holds tmux's bundled fallbacks and compat.h includes <imsg.h>.
    grep -q '^CPPFLAGS = -I\./compat' "$mf" || \
        sed -i 's|^CPPFLAGS = |CPPFLAGS = -I./compat |' "$mf"

    # ---- features iOS 10 does not actually have ----
    # closefrom()      : FreeBSD/macOS only; called in the forked child, so a
    #                    missing symbol makes every new pane abort
    # fdforkpty()      : OpenBSD only (tmux supplies getptmfd() itself)
    # explicit_bzero() : glibc/BSD; absent from iOS 10
    # setproctitle()   : absent from iOS
    # freezero()       : OpenBSD only
    # getdtablecount() : OpenBSD only
    # getpeereid()     : BSD, absent from iOS
    # imsg_*()         : OpenBSD only (tmux bundles its own)
    # htonll/ntohll()  : absent from iOS
    # tiparm_s()       : ncurses 6 only; the device ships ncurses 5.7
    # prctl/SO_PEERCRED/PROC_PID/GETPEERUCRED: Linux/BSD process introspection
    local m
    for m in CLOSEFROM FDFORKPTY EXPLICIT_BZERO SETPROCTITLE FREEZERO \
             GETDTABLECOUNT GETPEERUCRED IMSG HTONLL NTOHLL TIPARM TIPARM_S \
             PRCTL SO_PEERCRED PROC_PID; do
        sed -i "s/ -DHAVE_$m=1//g" "$mf"
    done

    # ---- link tmux's own implementations instead ----
    local o
    for o in closefrom fdforkpty explicit_bzero setproctitle freezero \
             getdtablecount getpeereid imsg imsg-buffer htonll ntohll; do
        [ -f "$d/compat/$o.c" ] || continue
        grep -q "compat/$o\.o" "$mf" || \
            sed -i "s|^LIBOBJS = \(.*\)$|LIBOBJS = \1 compat/$o.o|" "$mf"
    done

    # ncurses is not built: the device already ships libncursesw.
    if [ -n "$ncdylib" ] && ! grep -q "$ncdylib" "$mf"; then
        sed -i "s|^LIBS = |LIBS = $ncdylib |" "$mf"
    fi
    return 0
}
