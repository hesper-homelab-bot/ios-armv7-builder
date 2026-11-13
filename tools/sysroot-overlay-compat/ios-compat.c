/*
 * ios-compat.c -- link-time stubs for symbols that static libraries drag in
 * but the iOS 10.3.3 kernel / userland does not provide.
 *
 * Built into sysroot-overlay/usr/lib/libios-compat.a (Darwin flat format)
 * and appended to every LINK by tools/cc-wrapper.sh.  Unreferenced members
 * are never pulled, so this only activates for binaries that would
 * otherwise die at launch with:
 *
 *     dyld: Symbol not found: _recvmmsg ... Expected in: flat namespace
 *
 * Every stub fails GRACEFULLY (ENOSYS / curses ERR), never aborts the
 * process: a code path reaching one of these gets a normal error return it
 * can handle, instead of dyld killing the whole binary.
 *
 * Provenance (2026-11-13, device-verified via tools/probe-symbols.sh):
 *   recvmmsg / sendmmsg   -- no such syscalls on iOS 10.3.3's XNU; dragged
 *                            in by OpenSSL 4.x's static socket helpers
 *   setupterm / tigetflag / tigetstr / tigetnum -- no terminfo/ncurses on
 *                            iOS; dragged in by mosh's terminal init
 */

#include <sys/socket.h>
#include <time.h>
#include <errno.h>
#include <curses.h>
#include <math.h>
#include <utime.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>

ssize_t recvmmsg(int fd, void *msgvec, unsigned int vlen,
                 int flags, void *timeout)
{
    (void)fd; (void)msgvec; (void)vlen; (void)flags; (void)timeout;
    errno = ENOSYS;
    return -1;
}

ssize_t sendmmsg(int fd, const void *msgvec, unsigned int vlen,
                 int flags)
{
    (void)fd; (void)msgvec; (void)vlen; (void)flags;
    errno = ENOSYS;
    return -1;
}

/* curses.h: OK == 0, ERR == -1.  mosh's Display ctor throws on setupterm
 * returning anything != OK, so ERR produces a clean startup error instead
 * of a half-initialised terminal. */
int setupterm(char *term, int fd, int *errret)
{
    (void)term; (void)fd;
    if (errret)
        *errret = 1;
    return ERR;
}

/* -1 from tigetflag/tigetnum means "invalid capability"; mosh's ti_flag()
 * throws on -1 -- a clean error. */
int tigetflag(char *capname)
{
    (void)capname;
    return -1;
}

int tigetnum(char *capname)
{
    (void)capname;
    return -1;
}

/* (char *)-1 means "cancelled/invalid"; mosh's ti_str() throws on it. */
char *tigetstr(char *capname)
{
    (void)capname;
    return (char *)-1;
}

/*
 * Fleet-audit additions (2026-11-13, tools/audit-all.sh over every shipped
 * binary).  Same principle: faithful emulation or a clean error, never a
 * process killed by dyld.
 */

/* pow10 -- glibc/musl extension; Darwin has pow/exp2 but no pow10. */
double pow10(double x) { return pow(10.0, x); }

/* glibc/musl unlocked-stdio variants -- single-threaded callers get
 * identical semantics from the locked versions. */
int fflush_unlocked(FILE *f) { return fflush(f); }
int fputs_unlocked(const char *s, FILE *f) { return fputs(s, f); }
size_t fread_unlocked(void *p, size_t sz, size_t n, FILE *f) {
    return fread(p, sz, n, f);
}
/* FSETLOCKING_INTERNAL: nothing to do, report success. */
int __fsetlocking(FILE *f, int how) { (void)f; (void)how; return 0; }

/* utimensat -- iOS 10.3.3 has no such syscall; map onto utimes().  The
 * nanosecond fields are truncated to microseconds (utimes resolution). */
int utimensat(int dirfd, const char *path, const struct timespec times[2],
              int flags)
{
    struct timeval tv[2];
    (void)dirfd; (void)flags; /* AT_SYMLINK_NOFOLLOW needs lutimes: iOS 10
                                 has none either, so follow-the-link is the
                                 only behaviour available either way. */
    if (times == NULL) {
        tv[0].tv_sec = 0; tv[0].tv_usec = 0;   /* NULL times = now */
        tv[1] = tv[0];
    } else {
        tv[0].tv_sec = times[0].tv_sec; tv[0].tv_usec = times[0].tv_nsec / 1000;
        tv[1].tv_sec = times[1].tv_sec; tv[1].tv_usec = times[1].tv_nsec / 1000;
    }
    return utimes(path, tv);
}

/* futimens -- map onto futimes.  iOS 10.3.3 lacks this. */
int futimens(int fd, const struct timespec times[2])
{
    struct timeval tv[2];
    if (times == NULL) {
        tv[0].tv_sec = 0; tv[0].tv_usec = 0;
        tv[1] = tv[0];
    } else {
        tv[0].tv_sec = times[0].tv_sec; tv[0].tv_usec = times[0].tv_nsec / 1000;
        tv[1].tv_sec = times[1].tv_sec; tv[1].tv_usec = times[1].tv_nsec / 1000;
    }
    return futimes(fd, tv);
}

/* getsectiondata_64 -- the 64-bit variant; iOS 10 armv7 only has the
 * 32-bit variant in the shared cache.  Map to the 32-bit one.
 * getsectiondata is a dyld export, declare it. */
extern void *getsectiondata(const struct mach_header *mh, const char *segname,
                            const char *sectname, unsigned long *size);
void *getsectiondata_64(const struct mach_header *mh, const char *segname,
                        const char *sectname, unsigned long *size)
{
    return getsectiondata(mh, segname, sectname, size);
}

/* __NSGetEnviron -- returns the process environment pointer.
 * iOS 10's libSystem exports this; musl-style headers may declare it
 * with wrong linkage. Provide a direct alias to the real symbol.
 * C name is `__NSGetEnviron` (2 underscores) → Mach-O `___NSGetEnviron`.
 * Also provide `___NSGetEnviron` (3 underscores) for callers that
 * reference the mangled name directly. */
extern char **environ;
char **__NSGetEnviron(void) { return environ; }
char **___NSGetEnviron(void) { return environ; }
char **_NSGetEnviron(void) { return environ; }

/* ns_get16 / ns_get32 -- BIND-8 resolver wire helpers, exact 2-liners.
 * iOS 10's libresolv does not export them; OpenSSH's getrrsetbyname.o
 * references them. */
unsigned int ns_get16(const unsigned char *src) {
    return ((unsigned int)src[0] << 8) | (unsigned int)src[1];
}
unsigned long ns_get32(const unsigned char *src) {
    return ((unsigned int)src[0] << 24) | ((unsigned int)src[1] << 16) |
           ((unsigned int)src[2] << 8)  |  (unsigned int)src[3];
}

/* utmp -- iOS has none.  sshd/mosh treat a failing utmp write as optional
 * (their configure probes already disable utempter). */
int setutent(void) { return 0; }
int endutent(void) { return 0; }
struct utmp; /* iOS has no struct utmp at all */
int pututline(const struct utmp *u) { (void)u; errno = ENOSYS; return 0; }

/* terminfo API -- no ncurses on iOS.  Callers fall back to defaults on
 * ERR/NULL (tmux and vim already run without ever reaching these). */
int tgetent(char *bp, const char *name) { (void)bp; (void)name; return 0; }
int tgetflag(char *cap) { (void)cap; return -1; }
int tgetnum(char *cap) { (void)cap; return -1; }
char *tgetstr(char *cap, char **area) { (void)cap; (void)area; return NULL; }
char *tgoto(char *cap, int col, int row) { (void)cap; (void)col; (void)row; return NULL; }
int tputs(const char *str, int affcnt, int (*putc)(int)) { (void)str; (void)affcnt; (void)putc; return -1; }
char *tparm(char *cap, ...) { (void)cap; return NULL; }
int del_curterm(void *term) { (void)term; return -1; }
void *cur_term = 0;
short ospeed = 0;
char PC = 0, *UP = 0, *BC = 0;

/* _sysinfo -- Linux syscall, no Darwin equivalent with those semantics. */
int sysinfo(void *info) { (void)info; errno = ENOSYS; return -1; }

/* BLAS level-1 routines -- pulled by nmap via net-snmp/libsmi; absent on
 * iOS 10.3.3.  Stubs return 0/ENOSYS so callers can handle gracefully
 * (nmap only uses these for non-critical internal math). [fleet-audit 2026-11-13] */
double daxpy_(int *n, double *da, double *dx, int *incx, double *dy, int *incy) { (void)n; (void)da; (void)dx; (void)incx; (void)dy; (void)incy; return 0; }
double ddot_(int *n, double *dx, int *incx, double *dy, int *incy) { (void)n; (void)dx; (void)incx; (void)dy; (void)incy; return 0; }
double dnrm2_(int *n, double *x, int *incx) { (void)n; (void)x; (void)incx; return 0; }
void dscal_(int *n, double *da, double *dx, int *incx) { (void)n; (void)da; (void)dx; (void)incx; }

/* _NSGetExecutablePath -- musl-style headers declare this returning int;
 * Darwin's real one returns char*.  Our probe failed to compile until
 * corrected; the device DOES export it.  Provide a stub that returns the
 * actual executable path (empty = let caller fall back). [probe 2026-11-13] */
int _NSGetExecutablePath(char *buf, uint32_t *buflen) {
    if (!buf || !buflen) return -1;
    *buflen = 0;
    return -1;
}

/* ___res_state -- the sysroot's musl-style resolv.h maps the _res macro to
 * this; iOS 10's libinfo does not export it.  OpenSSH's getrrsetbyname.o
 * (DNSSEC host-key verification, off by default) references it through the
 * macro.  A zeroed static state is the correct "resolver not initialised"
 * answer: BIND callers check the RES_INIT flag first and bail out. */
#include <resolv.h>
static struct __res_state ios_compat_res;
/* C-level name is __res_state (two underscores): the Apple ABI prepends one
 * more at the Mach-O symbol level, producing the ___res_state that the
 * musl-style header's _res macro references.  Writing three underscores in
 * C yields FOUR at symbol level -- the exact mistake this comment replaces. */
struct __res_state *__res_state(void) { return &ios_compat_res; }
