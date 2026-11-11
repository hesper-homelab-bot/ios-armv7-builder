#ifndef _FCNTL_H
#define _FCNTL_H

#ifdef __cplusplus
extern "C" {
#endif

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

/* Darwin open-flag bits used as fd status bits (xnu bsd/sys/fcntl.h):
 * they appear in F_GETFL results and in the fd flags that proc_info
 * reports.  Not open() flags -- do not confuse with O_RDONLY etc. */
#define FREAD           0x0001
#define FWRITE          0x0002
#define FASYNC          0x0040  /* kernel/compat: same bits as O_ASYNC */
#define FFSYNC          0x0080  /* kernel: same bits as O_FSYNC/O_SYNC */
#define FNONBLOCK       0x0004  /* kernel/compat: same bits as O_NONBLOCK */
#define FAPPEND         0x0008  /* kernel/compat: same bits as O_APPEND */
#define FMARK           0x1000
#define FDEFER          0x2000
#define FHASLOCK        0x4000

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

/*
 * Darwin-only requests.  libuv's kqueue.c calls
 * fcntl(fd, F_GETPATH, path) to turn a descriptor back into a path.
 *
 * F_GETPATH is 50.  That value is not taken from a header -- it was
 * measured on the device (2026-11-08) by scanning request codes 45..55
 * against an open descriptor and looking for the one that fills the
 * buffer with a path: code 50 returned
 * "/private/var/mobile/scratch/fgetpath-probe", i.e. the real path of the
 * fd being queried.  The neighbouring Darwin values (F_FULLFSYNC=51,
 * F_NOCACHE=48, F_RDAHEAD=45) are consistent with the same band.
 */
#ifndef F_GETPATH
#define F_GETPATH       50
#endif
#ifndef F_PUNCHHOLE
#define F_PUNCHHOLE     99
#endif

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

/*
 * Darwin additions.
 *
 * AT_* are the *at() family flags.  Note for anyone tempted to use the
 * non-zero ones: iOS 10 implements the *at() calls but rejects every
 * non-zero flag at runtime (measured on this device while porting tmux),
 * so only AT_FDCWD is genuinely usable -- the rest are declared for
 * source compatibility with code that passes them through on other
 * platforms.
 *
 * F_FULLFSYNC is Darwin's "fsync and ask the drive to flush its cache",
 * which is a real request code (51), not a no-op alias of fsync.
 */
#ifndef AT_FDCWD
#define AT_FDCWD		-2
#endif
#ifndef AT_EACCESS
#define AT_EACCESS		0x0010
#endif
#ifndef AT_SYMLINK_NOFOLLOW
#define AT_SYMLINK_NOFOLLOW	0x0020
#endif
#ifndef AT_SYMLINK_FOLLOW
#define AT_SYMLINK_FOLLOW	0x0040
#endif
#ifndef AT_REMOVEDIR
#define AT_REMOVEDIR		0x0080
#endif
#ifndef F_FULLFSYNC
#define F_FULLFSYNC		51
#endif
#ifndef F_NOCACHE
#define F_NOCACHE		48
#endif
#ifndef F_RDAHEAD
#define F_RDAHEAD		45
#endif

int open(const char *, int, ...);
int openat(int, const char *, int, ...);
int fcntl(int, int, ...);
int creat(const char *, mode_t);

#ifdef __cplusplus
}
#endif

#endif
