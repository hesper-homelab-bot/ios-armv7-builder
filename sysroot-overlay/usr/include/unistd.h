#ifndef _UNISTD_H
#define _UNISTD_H
#include <features.h>
#define __NEED_size_t
#define __NEED_ssize_t
#define __NEED_off_t
#define __NEED_intptr_t
#define __NEED_pid_t
#define __NEED_uid_t
#define __NEED_gid_t
#define __NEED_useconds_t

/* The process environment.  musl puts this in unistd.h; this curated
 * overlay replaces that header, and Dropbear's clearenv fallback reads
 * environ[0] directly, so it has to stay declared. */
extern char **environ;
#include <bits/alltypes.h>

/*
 * One extern "C" block for all declarations: this header (and
 * <termios.h>) were the last two without one, so tcgetpgrp/tcsetpgrp and
 * friends got C++ linkage here while <termios.h> gave them C linkage,
 * which is a hard "different language linkage" error in C++4 code.
 */
#ifdef __cplusplus
extern "C" {
#endif

#define STDIN_FILENO  0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#define F_OK 0
#define R_OK 4
#define W_OK 2
#define X_OK 1

ssize_t read(int, void *, size_t);
ssize_t write(int, const void *, size_t);
off_t lseek(int, off_t, int);
int close(int);
int dup(int);
int dup2(int, int);
int pipe(int[2]);
int isatty(int);
int access(const char *, int);
int chdir(const char *);
int fchdir(int);
char *getcwd(char *, size_t);
int chown(const char *, uid_t, gid_t);
int fchown(int, uid_t, gid_t);
int link(const char *, const char *);
int unlink(const char *);
int rmdir(const char *);
int symlink(const char *, const char *);
ssize_t readlink(const char *__restrict, char *__restrict, size_t);
int execl(const char *, const char *, ...);
int execv(const char *, char *const[]);
int execve(const char *, char *const[], char *const[]);
int execlp(const char *, const char *, ...);
int execvp(const char *, char *const[]);
int fork(void);
pid_t getpid(void);
pid_t getppid(void);
pid_t getpgid(pid_t);
pid_t setsid(void);
/* Missing from musl's predicates but present on iOS -- each one verified by
   calling it in a test program on the device (iPad 4, iOS 10.3.3).
   wget's log.c needs getpgrp() and fails to compile without it. */
pid_t getpgrp(void);
int setpgrp(void);
uid_t getuid(void);
uid_t geteuid(void);
gid_t getgid(void);
gid_t getegid(void);
int setuid(uid_t);
int setgid(gid_t);
int setpgid(pid_t, pid_t);
int getgroups(int, gid_t[]);
int nice(int);
void _exit(int) __attribute__((noreturn));
unsigned alarm(unsigned);
unsigned sleep(unsigned);
int pause(void);
char *ttyname(int);
int ttyname_r(int, char *, size_t);
int fsync(int);
/* POSIX; musl declares these in its own unistd.h, which this overlay
   replaces wholesale, so they have to be repeated here.  wget's hsts.c
   calls ftruncate() and fails to compile without the declaration. */
int truncate(const char *, off_t);
int ftruncate(int, off_t);
int fdatasync(int);
void *sbrk(intptr_t);
useconds_t ualarm(useconds_t, useconds_t);
/* glibc spells the /etc/shells iterator this way; Darwin and iOS have it,
 * verified on the device (each one returns when called).  musl declares only
 * login_tty, so Dropbear's svr-auth.c shell-check loop fails to compile. */
char *getusershell(void);
void  setusershell(void);
void  endusershell(void);

/* setegid: present on iOS (verified), absent from musl's declarations. */
int setegid(gid_t);
int seteuid(uid_t);

/* daemon() is BSD/Darwin and present on iOS; musl does not declare it.
   Dropbear svr-main.c needs it to detach from the terminal. */
int daemon(int, int);

/* getpass reads a password from the controlling terminal without echo.  musl
 * does not declare it; Darwin and iOS both have it. */
char *getpass(const char *);

/* POSIX getopt() and its variables.  musl's unistd.h declares all of these;
 * this overlay replaces that header wholesale, and the omission only shows up
 * when something includes <unistd.h> and calls getopt -- which is exactly how
 * Dropbear's bundled scp.c failed to compile. */
int getopt(int, char *const[], const char *);
/* getopt_long's 4th parameter is struct option (defined in <getopt.h>).
 * It used to be declared here as const void *, which made every file that
 * includes BOTH <unistd.h> and <getopt.h> (tcpdump.c was the first) fail
 * with conflicting-types.  Forward-declare the struct instead. */
struct option;
int getopt_long(int, char *const[], const char *, const struct option *, int *);
int getopt_long_only(int, char *const[], const char *, const struct option *, int *);
extern char *optarg;
extern int optind, opterr, optopt;

/* Remaining POSIX/XSI/BSD declarations musl has and this curated overlay
 * dropped.  Each is part of the base OS interface rather than a GNU or Linux
 * extension, so they are expected on iOS too; they are declared here so that
 * a future port does not rediscover them one compile error at a time.
 * Deliberately NOT included: eaccess/euidaccess/posix_close (glibc),
 * getentropy/gettid/copy_file_range/dup3/pipe2/fexecve (Linux), vfork/vhangup,
 * and the *at() family, which iOS 10 partly lacks. */
int     pread(int, void *, size_t, off_t);
int     pwrite(int, const void *, size_t, off_t);
int     lockf(int, int, off_t);
void    swab(const void *__restrict, void *__restrict, ssize_t);
int     chroot(const char *);
int     lchown(const char *, uid_t, gid_t);
void    sync(void);
int     getdomainname(char *, size_t);
int     setdomainname(const char *, size_t);
long    gethostid(void);
void    sethostname(const char *, size_t);
char   *getlogin(void);
int     getlogin_r(char *, size_t);

long sysconf(int);
long pathconf(const char *, int);
long fpathconf(int, int);
int gethostname(char *, size_t);
unsigned int sleep(unsigned int);
int usleep(useconds_t);
void closefrom(int);

/* pathconf()/fpathconf() selectors (musl uses Linux numbering).
 *
 * Derived from the device, not from a header: /usr/include does not exist on
 * a jailbroken iOS box, so each selector was called through pathconf() and
 * fpathconf() on real paths and matched against the value it is defined to
 * return.
 *
 *   sel 4 -> 255     and a binary search over open() showed the filesystem
 *                    rejects a 256-character path component with
 *                    ENAMETOOLONG, so 255 is the true NAME_MAX.
 *   sel 5 -> 1024    which is Darwin's PATH_MAX.
 *   sel 1 -> 32767   the link limit.
 *   sel 0, 2, 3 -> EINVAL: Darwin has no LINK_MAX/MAX_INPUT/NAME_CHARS_MAX
 *                    selector at those numbers.
 *
 * wget's url.c calls get_max_length(..., _PC_NAME_MAX) to bound a filename
 * before shortening it; without this it does not compile.
 */
#define _PC_LINK_MAX		1
#define _PC_NAME_MAX		4
#define _PC_PATH_MAX		5
#define _PC_PIPE_BUF		6
#define _PC_CHOWN_RESTRICTED	7
#define _PC_NO_TRUNC		8
#define _PC_VDISABLE		8

/* Darwin sysconf() names (musl uses a different numbering) */
#define _SC_ARG_MAX		1
#define _SC_CHILD_MAX		2
#define _SC_CLK_TCK		3
#define _SC_NGROUPS_MAX		4
#define _SC_OPEN_MAX		5
#define _SC_JOB_CONTROL		6
#define _SC_SAVED_IDS		7
#define _SC_VERSION		8
#define _SC_NPROCESSORS_CONF	57
#define _SC_NPROCESSORS_ONLN	58
#define _SC_PAGESIZE		29
#define _SC_PAGE_SIZE		_SC_PAGESIZE
pid_t tcgetpgrp(int);
int tcsetpgrp(int, pid_t);
pid_t getsid(pid_t);
int getpagesize(void);
void setproctitle(const char *, ...);
int getdtablesize(void);
int getpeereid(int, uid_t *, gid_t *);
/* issetugid() -- BSD/Darwin way of asking "am I running setuid or setgid?".
   Verified present on the device (iPad 4, iOS 10.3.3): returns 0.
   gnulib's lib/secure_getenv.c selects its issetugid() branch on this, which
   is the correct one for OS X; the glibc branch it would otherwise pick
   calls __secure_getenv(), which does not exist here. */
int issetugid(void);

int setregid(gid_t, gid_t);
int setreuid(uid_t, uid_t);

/* getentropy() -- Darwin has it (it is in libSystem, unlike Linux's getrandom
   syscall wrapper, which iOS 10 does not export).  Verified on the device by
   compiling a caller and running it: it returns 0 and fills the buffer.
   musl's unistd.h (which this overlay replaces) does not declare it, and
   neither does any other header in the sysroot, so OpenSSH's entropy.c would
   compile it as an implicit declaration returning int.  Dropbear never hit
   this because it only probes getrandom. */
int getentropy(void *, size_t);

/* ---------------------------------------------------------------------------
 * setresgid()/setresuid() shims for Dropbear.
 *
 * Dropbear's sysoptions.h has a hard compile-time invariant:
 *
 *     #if DROPBEAR_SVR_DROP_PRIVS && !defined(HAVE_SETRESGID)
 *     #  error "DROPBEAR_SVR_DROP_PRIVS requires setresgid()."
 *     #endif
 *
 * and DROPBEAR_SVR_DROP_PRIVS is "change server process to user privileges
 * after authentication" -- disabling it would run every session as root.
 * So HAVE_SETRESGID has to stay definable.  iOS 10, however, does not export
 * either function (verified on the device: calling each aborts with
 * "dyld: lazy symbol binding failed: Symbol not found: _setresgid").
 *
 * The situation is not actually bad, because of what Dropbear uses:
 *
 *   * the real privilege drop uses setgid(), initgroups() and setuid(),
 *     all of which DO exist on iOS;
 *   * setresgid appears exactly once in the whole tree, svr-auth.c:519, to
 *     retain the utmp group so wtmp records can be written.  That call
 *     already checks its return value and sets have_utmp_gid only on
 *     success, so returning failure takes a path Dropbear is designed to
 *     handle -- and we disable utmp anyway.
 *
 * So these shims exist to keep Dropbear's invariant true while letting that
 * one call fail cleanly.  static inline keeps them out of the archive, so
 * configure's link test for setresgid (which crosses a shared-library
 * boundary) still reports "no", which is the honest answer.
 * ------------------------------------------------------------------------- */
static inline int setresgid(gid_t r, gid_t e, gid_t s)
{
	(void)s;	/* no way to set the saved id alone on iOS */
	if (r == (gid_t)-1 || e == (gid_t)-1)
		return -1;	/* caller wants "saved only": let it fall back */
	return setregid(r, e);
}

static inline int setresuid(uid_t r, uid_t e, uid_t u)
{
	(void)u;
	if (r == (uid_t)-1 || e == (uid_t)-1)
		return -1;
	return setreuid(r, e);
}

/* setlogin()/getlogin() -- BSD utmp-name setters/getter.  Both are present in
   iOS's libSystem (verified on the device: each returns normally) but musl,
   whose unistd.h this overlay replaces, declares neither.  OpenSSH's session.c
   calls setlogin() when UseLogin is enabled, so it needs the prototype. */
int setlogin(const char *);

/* ctermid() is stdio.h's; declaring it here too collides with libc++'s
   cstdio -> stdio.h path in C++ (different language linkage). */
char *getlogin(void);

/*
 * confstr() with the Darwin user-dir selectors (Apple Libc-1244.30.3
 * include/unistd.h).  On iOS _CS_DARWIN_USER_TEMP_DIR falls back to
 * getenv("TMPDIR"); confstr itself is exported by libSystem (verified on
 * device 2026-11-07: returns the sandbox temp path).
 */
#define _CS_DARWIN_USER_DIR		65536
#define _CS_DARWIN_USER_TEMP_DIR	65537
#define _CS_DARWIN_USER_CACHE_DIR	65538
size_t	confstr(int, char *, size_t);

#ifdef __cplusplus
}
#endif

#endif /* _UNISTD_H */
