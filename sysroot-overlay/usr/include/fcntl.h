#ifndef _FCNTL_H
#define _FCNTL_H
#include <bits/alltypes.h>
#define __NEED_mode_t
#include <bits/alltypes.h>
#define __NEED_off_t
#include <bits/alltypes.h>

#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0100
#define O_EXCL 0200
#define O_TRUNC 01000
#define O_APPEND 02000
#define O_NONBLOCK 04000
#define O_SYNC 040000
#define O_CLOEXEC 02000000

#define FD_CLOEXEC 1
#define F_DUPFD 0
#define F_GETFD 1
#define F_SETFD 2
#define F_GETFL 3
#define F_SETFL 4
#define F_GETLK 5
#define F_SETLK 6
#define F_SETLKW 7

struct flock {
    short l_type;
    short l_whence;
    off_t l_start;
    off_t l_len;
    pid_t l_pid;
};

int open(const char *, int, ...);
int openat(int, const char *, int, ...);
int fcntl(int, int, ...);
int creat(const char *, mode_t);
#endif
