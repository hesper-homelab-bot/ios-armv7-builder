#ifndef _SYS_STAT_H
#define _SYS_STAT_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <bits/alltypes.h>
#define __NEED_mode_t
#include <bits/alltypes.h>
#define __NEED_dev_t
#include <bits/alltypes.h>
#define __NEED_ino_t
#include <bits/alltypes.h>
#define __NEED_nlink_t
#include <bits/alltypes.h>
#define __NEED_uid_t
#include <bits/alltypes.h>
#define __NEED_gid_t
#include <bits/alltypes.h>
#define __NEED_off_t
#include <bits/alltypes.h>
#define __NEED_time_t
#include <bits/alltypes.h>
#define __NEED_blksize_t
#include <bits/alltypes.h>
#define __NEED_blkcnt_t
#include <bits/alltypes.h>
#define __NEED_struct_timespec
#include <bits/alltypes.h>

struct stat {
    int32_t  st_dev;
    uint16_t st_mode;
    uint16_t st_nlink;
    uint64_t st_ino;
    uint32_t st_uid;
    uint32_t st_gid;
    int32_t  st_rdev;
    struct timespec st_atimespec;
    struct timespec st_mtimespec;
    struct timespec st_ctimespec;
    struct timespec st_birthtimespec;
    int64_t  st_size;
    int64_t  st_blocks;
    int32_t  st_blksize;
    uint32_t st_flags;
    uint32_t st_gen;
    int32_t  st_lspare;
    int64_t  st_qspare[2];
};
/* Darwin/POSIX aliases */
#define st_atime st_atimespec.tv_sec
#define st_mtime st_mtimespec.tv_sec
#define st_ctime st_ctimespec.tv_sec
#define st_birthtime st_birthtimespec.tv_sec
#define st_atim st_atimespec
#define st_mtim st_mtimespec
#define st_ctim st_ctimespec
/* gnulib's stat-time.h uses the bare st_*tim names once it sees the
   *_TV_NSEC probes succeed; without st_birthtim it fails to compile with
   "no member named 'st_birthtim' in 'struct stat'". */
#define st_birthtim st_birthtimespec

int stat(const char *__restrict, struct stat *__restrict);
int fstat(int, struct stat *);
int lstat(const char *__restrict, struct stat *__restrict);
int chmod(const char *, mode_t);
int fchmod(int, mode_t);
int mkdir(const char *, mode_t);
int mkfifo(const char *, mode_t);
mode_t umask(mode_t);

#define S_IFMT   0170000
#define S_IFDIR  0040000
#define S_IFCHR  0020000
#define S_IFBLK  0060000
#define S_IFREG  0100000
#define S_IFIFO  0010000
#define S_IFLNK  0120000
#define S_IFSOCK 0140000
#define S_ISDIR(m)  (((m) & S_IFMT) == S_IFDIR)
#define S_ISCHR(m)  (((m) & S_IFMT) == S_IFCHR)
#define S_ISBLK(m)  (((m) & S_IFMT) == S_IFBLK)
#define S_ISREG(m)  (((m) & S_IFMT) == S_IFREG)
#define S_ISFIFO(m) (((m) & S_IFMT) == S_IFIFO)
#define S_ISLNK(m)  (((m) & S_IFMT) == S_IFLNK)
#define S_ISSOCK(m) (((m) & S_IFMT) == S_IFSOCK)
#define S_ISUID  0004000
#define S_ISGID  0002000
#define S_ISVTX  0001000
#define S_IRWXU  0000700
#define S_IRUSR  0000400
#define S_IWUSR  0000200
#define S_IXUSR  0000100
#define S_IRWXG  0000070
#define S_IRGRP  0000040
#define S_IWGRP  0000020
#define S_IXGRP  0000010
#define S_IRWXO  0000007
#define S_IROTH  0000004
#define S_IWOTH  0000002
#define S_IXOTH  0000001
#define ACCESSPERMS (S_IRWXU|S_IRWXG|S_IRWXO)
#define ALLPERMS (S_ISUID|S_ISGID|S_ISVTX|ACCESSPERMS)
#define DEFFILEMODE (S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH)
int chmod(const char *, mode_t);
int fchmodat(int, const char *, mode_t, int);
int mkdirat(int, const char *, mode_t);
int mkfifoat(int, const char *, mode_t);
/* The last three are present in iOS's libSystem but musl, whose sys/stat.h
   this overlay replaces, stops at futimens().  OpenSSH's sftp-server.c calls
   utimensat() and fchownat() with flag 0 for the SFTP "setstat" command, so
   without these declarations the build fails with
   "call to undeclared function 'utimensat'" / 'fchownat'. */
int utimensat(int, const char *, const struct timespec *, int);
int fchownat(int, const char *, uid_t, gid_t, int);
/* (futimesat() is declared by <sys/time.h>, which this file does not include --
   adding it here would conflict.) */
int futimens(int, const struct timespec *);

/*
 * Darwin special timestamp values for utimensat()/futimens(): "set to
 * now" and "leave this one alone" instead of a literal time.  musl, whose
 * sys/stat.h this overlay replaces, declares the functions without these.
 */
#ifndef UTIME_NOW
#define UTIME_NOW	-1
#define UTIME_OMIT	-2
#endif


#ifdef __cplusplus
}
#endif

#endif
