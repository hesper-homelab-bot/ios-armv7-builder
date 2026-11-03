#ifndef _FCNTL_H
#define _FCNTL_H
#include <sys/types.h>

/*
 * Darwin (iOS) open/fcntl flag values.
 *
 * The Linux values differ starting with O_NONBLOCK (0x800 there, 0x4 here).
 * Getting this wrong makes every fcntl(F_SETFL, O_NONBLOCK) a silent no-op,
 * leaving every socket blocking - which hung the tmux client inside
 * libevent's signal-pipe drain loop and poisoned everything else that
 * assumed non-blocking I/O.
 */

#define O_RDONLY        0x0000
#define O_WRONLY        0x0001
#define O_RDWR          0x0002
#define O_ACCMODE       0x0003
#define O_NONBLOCK      0x0004
#define O_APPEND        0x0008
#define O_SHLOCK        0x0010
#define O_EXLOCK        0x0020
#define O_ASYNC         0x0040
#define O_FSYNC         0x0080
#define O_SYNC          0x0080
#define O_NOFOLLOW      0x0100
#define O_CREAT         0x0200
#define O_TRUNC         0x0400
#define O_EXCL          0x0800
#define O_EVTONLY       0x8000
#define O_CLOEXEC       0x1000000
#define O_NOCTTY        0
#define O_NDELAY        O_NONBLOCK
#define O_DSYNC         O_SYNC
#define O_RSYNC         O_SYNC
#define O_DIRECTORY     0
#define O_DIRECT        0
#define O_LARGEFILE     0
#define O_NOATIME       0
#define O_PATH          0
#define O_TMPFILE       0

#define FD_CLOEXEC      1

#define F_DUPFD         0
#define F_GETFD         1
#define F_SETFD         2
#define F_GETFL         3
#define F_SETFL         4
#define F_GETOWN        5
#define F_SETOWN        6
#define F_GETLK         7
#define F_SETLK         8
#define F_SETLKW        9

#define F_RDLCK         1
#define F_UNLCK         2
#define F_WRLCK         3

/* Darwin struct flock layout */
struct flock {
	off_t	l_start;
	off_t	l_len;
	pid_t	l_pid;
	short	l_type;
	short	l_whence;
};

int open(const char *, int, ...);
int openat(int, const char *, int, ...);
int fcntl(int, int, ...);
int creat(const char *, mode_t);
#endif
