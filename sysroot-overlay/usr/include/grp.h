#ifndef	_GRP_H
#define	_GRP_H

/* musl's grp.h declares getgrgid()/getgrnam() and friends but not the BSD
 * "gid to name" helper group_from_gid(), which iOS's libSystem does export
 * (verified on the device: links and returns).  OpenSSH's sftp-common.c calls
 * it alongside user_from_uid() for the default sftp listing. */

#ifdef __cplusplus
extern "C" {
#endif

#include <features.h>

#define __NEED_size_t
#define __NEED_gid_t

#ifdef _GNU_SOURCE
#define __NEED_FILE
#endif

#include <bits/alltypes.h>

struct group {
	char *gr_name;
	char *gr_passwd;
	gid_t gr_gid;
	char **gr_mem;
};

struct group  *getgrgid(gid_t);
struct group  *getgrnam(const char *);

int getgrgid_r(gid_t, struct group *, char *, size_t, struct group **);
int getgrnam_r(const char *, struct group *, char *, size_t, struct group **);

#if defined(_XOPEN_SOURCE) || defined(_GNU_SOURCE) || defined(_BSD_SOURCE)
struct group  *getgrent(void);
void           endgrent(void);
void           setgrent(void);
#endif

#ifdef _GNU_SOURCE
struct group  *fgetgrent(FILE *);
int           putgrent(const struct group *, FILE *);
#endif

/*
 * Standard BSD/Darwin group-management calls.  They must also be visible
 * for _DARWIN_C_SOURCE and plain __APPLE__: libuv compiles with
 * -D_DARWIN_C_SOURCE rather than _GNU_SOURCE, and its spawn path calls
 * setgroups(), which was resolving to an implicit declaration.
 *
 * Note the first parameter is int, not size_t -- Darwin's signature is
 *     int setgroups(int ngroups, const gid_t *grouplist);
 * (verified against the sysroot's own usage and the libSystem behaviour
 * on device: setgroups(0, NULL) returns -1/EPERM for an unprivileged
 * process rather than failing to link).
 */
#if defined(_GNU_SOURCE) || defined(_BSD_SOURCE) || defined(_DARWIN_C_SOURCE) || \
    defined(__APPLE__)
int getgrouplist(const char *, gid_t, gid_t *, int *);
int setgroups(int, const gid_t *);
int initgroups(const char *, gid_t);
#endif

/* (gid, noname): noname selects numeric output instead of the group name. */
const char *group_from_gid(gid_t, int);

#ifdef __cplusplus
}
#endif

#endif
