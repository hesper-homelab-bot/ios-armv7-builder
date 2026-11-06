/* Darwin <dirent.h>.
 *
 * Replaces the musl one this sysroot otherwise falls back to.  The struct
 * itself lives in <bits/dirent.h> -- see the measured layout documented there;
 * this header only has to declare what Darwin actually declares.
 *
 * Two deliberate differences from the musl version it shadows, both about
 * *symbols* rather than about the struct:
 *
 *   * no getdents().  Darwin has getdirentries(2), not the Linux getdents(2),
 *     and iOS 10 exports no _getdents.  Declaring a function the target libc
 *     does not have is only safe while nothing calls it -- the first port that
 *     does would link fine and then die inside dyld's lazy binding, possibly in
 *     a child process re-exec'd after a successful handshake.
 *   * d_fileno stays defined as d_ino.  Apple does not define it, but it costs
 *     nothing (same offset, same value) and portable code such as OpenBSD's
 *     getcwd(3) fallback reaches for it.
 *
 * The DT_* constants are left visible unconditionally rather than behind musl's
 * _GNU_SOURCE/_BSD_SOURCE gate: they are plain POSIX names, Darwin defines them
 * always, and their values are checked against the device below.
 */
#ifndef _DIRENT_H
#define _DIRENT_H

#ifdef __cplusplus
extern "C" {
#endif

#include <features.h>

#define __NEED_ino_t
#define __NEED_off_t
#if defined(_BSD_SOURCE) || defined(_GNU_SOURCE)
#define __NEED_size_t
#endif

#include <bits/alltypes.h>

#include <bits/dirent.h>

#ifndef __DARWIN_MAXNAMLEN
#define __DARWIN_MAXNAMLEN 255
#endif
#ifndef __DARWIN_MAXPATHLEN
#define __DARWIN_MAXPATHLEN 1024
#endif

typedef struct __dirstream DIR;

#define d_fileno d_ino

int            closedir(DIR *);
DIR           *fdopendir(int);
DIR           *opendir(const char *);
struct dirent *readdir(DIR *);
int            readdir_r(DIR *__restrict, struct dirent *__restrict,
		    struct dirent **__restrict);
void           rewinddir(DIR *);
int            dirfd(DIR *);

int            alphasort(const struct dirent **, const struct dirent **);
int            scandir(const char *, struct dirent ***,
		    int (*)(const struct dirent *),
		    int (*)(const struct dirent **, const struct dirent **));
int            versionsort(const struct dirent **, const struct dirent **);

void           seekdir(DIR *, long);
long           telldir(DIR *);

/* DT_* -- confirmed against the device: DT_DIR(4) for "." and "..", DT_REG(8)
 * for regular files, DT_LNK(10) for symlinks, DT_UNKNOWN(0) where the
 * filesystem does not say. */
#define DT_UNKNOWN 0
#define DT_FIFO 1
#define DT_CHR 2
#define DT_DIR 4
#define DT_BLK 6
#define DT_REG 8
#define DT_LNK 10
#define DT_SOCK 12
#define DT_WHT 14
#define IFTODT(x) ((x) >> 12 & 017)
#define DTTOIF(x) ((x) << 12)

#ifdef __cplusplus
}
#endif

#endif /* _DIRENT_H */
