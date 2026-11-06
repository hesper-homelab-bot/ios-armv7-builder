#ifndef _PWD_H
#define _PWD_H

#ifdef __cplusplus
extern "C" {
#endif

#include <features.h>

#define __NEED_size_t
#define __NEED_uid_t
#define __NEED_gid_t

#ifdef _GNU_SOURCE
#define __NEED_FILE
#endif

#include <bits/alltypes.h>

struct passwd {
	char	*pw_name;
	char	*pw_passwd;
	uid_t	 pw_uid;
	gid_t	 pw_gid;
	time_t	 pw_change;
	char	*pw_class;
	char	*pw_gecos;
	char	*pw_dir;
	char	*pw_shell;
	time_t	 pw_expire;
};

#if defined(_XOPEN_SOURCE) || defined(_GNU_SOURCE) || defined(_BSD_SOURCE)
void setpwent (void);
void endpwent (void);
struct passwd *getpwent (void);
#endif

struct passwd *getpwuid (uid_t);
struct passwd *getpwnam (const char *);
int getpwuid_r (uid_t, struct passwd *, char *, size_t, struct passwd **);
int getpwnam_r (const char *, struct passwd *, char *, size_t, struct passwd **);

#ifdef _GNU_SOURCE
struct passwd *fgetpwent(FILE *);
int putpwent(const struct passwd *, FILE *);
#endif

/* user_from_uid() -- BSD's "uid to name, with a numeric fallback" helper, with
   the signature (uid, noname) where noname selects numeric output.  Present in
   iOS's libSystem (verified on the device: links and returns).  musl's pwd.h,
   which this overlay replaces, stops at getpwnam_r.  OpenSSH's sftp-common.c
   calls it for the default "sftp -l" listing, so without the declaration it
   fails to compile with "call to undeclared function 'user_from_uid'". */
const char *user_from_uid(uid_t, int);

#ifdef __cplusplus
}
#endif

#endif

