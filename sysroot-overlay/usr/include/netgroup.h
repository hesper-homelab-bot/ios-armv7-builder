#ifndef _NETGROUP_H
#define _NETGROUP_H

/* musl ships no netgroup.h at all -- it has no netgroup implementation -- so any
 * build that #includes it (OpenSSH's auth-rhosts.c does so unconditionally)
 * dies with "file not found" unless a header is supplied.  iOS does have the
 * netgroup interface (verified on the device, iPad 4 / iOS 10.3.3: innetgr()
 * links and returns).  This supplies the prototypes.
 *
 * The empty netgroup.h that configure auto-generates in
 * openbsd-compat/include/ is not enough: it only lets the #include succeed and
 * leaves innetgr() undeclared, which fails with
 *     call to undeclared function 'innetgr'
 */

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Note the const on the first argument only: that matches Darwin's own
 * prototype, where the netgroup name is a mutable char* and the rest are
 * const.  Callers pass string literals, which is fine for the const ones. */
int innetgr(const char *netgroup, const char *host, const char *user,
    const char *domain);
int getnetgrent(char **machinep, char **userp, char **domainp);
int setnetgrent(const char *netgroup);
void endnetgrent(void);

#ifdef __cplusplus
}
#endif

#endif
