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
    # Do NOT force the select backend.  Stock tmux sets EVENT_NOKQUEUE and
    # EVENT_NOPOLL on Darwin, but on iOS 10 select() loses wakeups: a peer's
    # pending data does not make EV_READ fire, so a client's MSG_COMMAND is
    # read only by luck and MSG_EXIT is never seen - the client hangs forever.
    # kqueue behaves correctly (verified both with a minimal libevent program
    # on the device and in tmux itself); only poll is left disabled.
    sed -i '/setenv("EVENT_NOKQUEUE"/d' "$d/osdep-darwin.c"

    # libevent never reports EV_WRITE on this target, on either backend.  tmux
    # queues a message in proc_send() and relies on the event loop to flush it,
    # so MSG_EXIT in particular is never written and the peer waits forever.
    # Flush synchronously instead; anything that does not fit stays queued.
    python3 - "$d/proc.c" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """\tretval = imsg_compose(ibuf, type, PROTOCOL_VERSION, -1, fd, vp, len);
\tif (retval != 1)
\t\treturn (-1);

\tproc_update_event(peer);"""
new = """\tretval = imsg_compose(ibuf, type, PROTOCOL_VERSION, -1, fd, vp, len);
\tif (retval != 1)
\t\treturn (-1);

\t/* Flush now: EV_WRITE is never reported on this target. */
\tif (msgbuf_write(&ibuf->w) <= 0 && errno != EAGAIN)
\t\tlog_debug("msgbuf_write: %s", strerror(errno));

\tproc_update_event(peer);"""
if "EV_WRITE is never reported" not in s:
    assert old in s, "proc_send pattern not found"
    open(p, "w").write(s.replace(old, new, 1))
PYEOF
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
