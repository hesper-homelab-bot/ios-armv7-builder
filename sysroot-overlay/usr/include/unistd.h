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
#include <bits/alltypes.h>

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
#endif
