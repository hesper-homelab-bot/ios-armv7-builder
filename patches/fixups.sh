#!/bin/bash
# Idempotent source and Makefile fixups.
#
# Every item here exists because this target differs from a normal build.  The
# central hazard is that our linker allows undefined symbols (they resolve from
# the device's dylibs at runtime), so autoconf's AC_CHECK_FUNCS/AC_CHECK_FUNCS_
# ONCE probes *always succeed* — including for functions iOS does not have.
# Anything tmux/the OS failed to provide at load time aborts the process with
# "DYLD, Symbol not found", so each one has to be turned off by hand and
# replaced with the project's own bundled implementation.

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
    # NOTE: tmux deliberately forces the select backend on Darwin
    # (EVENT_NOKQUEUE/EVENT_NOPOLL) because kqueue and poll are unreliable for
    # non-socket descriptors there.  Leave that alone: re-enabling kqueue made
    # the server spin at 100% CPU in testing.
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
