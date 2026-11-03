#ifndef _UNISTD_H
#define _UNISTD_H
#include <features.h>
#define __NEED_size_t
#define __NEED_ssize_t
#define __NEED_off_t
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
long sysconf(int);
long pathconf(const char *, int);
int gethostname(char *, size_t);
unsigned int sleep(unsigned int);
int usleep(useconds_t);
void closefrom(int);

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
#endif
