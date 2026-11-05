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

    # Force the poll backend, whichever way the upstream source of the day
    # chokes the environment.  On iOS 10:
    #   - kqueue breaks the moment a pty master joins the event base: a
    #     minimal libevent program on the device stops reporting the listen
    #     socket entirely once a tty fd is registered (accept never fires).
    #   - select misbehaved as well; poll passed every check, including pty
    #     handling.
    # libevent reads these variables when the base is created, so set both
    # and unset them afterwards so pane children do not inherit them.
    python3 - "$d/osdep-darwin.c" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()

marker = "osdep_event_init(void)\n{"
i = s.find(marker)
if i < 0:
    raise SystemExit("osdep_event_init not found")
# back up to the start of the "struct event_base *" line
start = s.rfind("struct event_base *", 0, i)
# forward to the end of the function: first line that is exactly "}"
end = s.find("\n}\n", i)
if start < 0 or end < 0:
    raise SystemExit("osdep_event_init bounds not found")
end += len("\n}\n")

new_fn = (
    "struct event_base *\n"
    "osdep_event_init(void)\n"
    "{\n"
    "\tstruct event_base\t*base;\n"
    "\n"
    "\t/*\n"
    "\t * Force the poll backend on this target: kqueue breaks as soon as\n"
    "\t * a tty joins the event base and select's wakeups are unreliable.\n"
    "\t */\n"
    "\tsetenv(\"EVENT_NOKQUEUE\", \"1\", 1);\n"
    "\tsetenv(\"EVENT_NOPOLL\", \"1\", 1);\n"
    "\n"
    "\tbase = event_init();\n"
    "\n"
    "\tunsetenv(\"EVENT_NOKQUEUE\");\n"
    "\tunsetenv(\"EVENT_NOPOLL\");\n"
    "\n"
    "\treturn (base);\n"
    "}\n"
)

open(p, "w").write(s[:start] + new_fn + s[end:])
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
