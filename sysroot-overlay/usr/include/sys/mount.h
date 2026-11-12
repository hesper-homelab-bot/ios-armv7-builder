#ifndef _SYS_MOUNT_H
#define _SYS_MOUNT_H

/*
 * Darwin sys/mount.h for the iOS armv7 cross build.  musl's version is the
 * Linux layout and is useless here: getmntinfo()/getfsstat() return
 * Darwin struct statfs, and the kernel copies the Darwin layout into the
 * caller's buffer.
 *
 * On iOS 10 (armv7) the 64-bit-inode variant is the only one, so struct
 * statfs == struct statfs64.  Every field verified against
 * xnu-3789.70.16 bsd/sys/mount.h (__DARWIN_STRUCT_STATFS64).
 */

#include <sys/cdefs.h>		/* __BEGIN_DECLS / __END_DECLS below */
#include <sys/types.h>
#include <sys/socket.h>		/* sa_family_t */
/* struct statfs embeds char f_mntonname[MAXPATHLEN]; Darwin's mount.h
   gets the constant from sys/param.h.  Ours must include it too, or
   every consumer of <sys/mount.h> fails with "undeclared identifier
   MAXPATHLEN" (nginx's own core sources were the first to hit it). */
#include <sys/param.h>

#define MFSNAMELEN	15	/* length of fs type name, not inc. null */
#define MFSTYPENAMELEN	16	/* length of fs type name including null */

typedef struct fsid { int32_t val[2]; } fsid_t;

struct statfs {
	uint32_t	f_bsize;	/* fundamental file system block size */
	int32_t		f_iosize;	/* optimal transfer block size */
	uint64_t	f_blocks;	/* total data blocks in file system */
	uint64_t	f_bfree;	/* free blocks in fs */
	uint64_t	f_bavail;	/* free blocks avail to non-superuser */
	uint64_t	f_files;	/* total file nodes in file system */
	uint64_t	f_ffree;	/* free file nodes in fs */
	fsid_t		f_fsid;		/* file system id */
	uid_t		f_owner;	/* user that mounted the filesystem */
	uint32_t	f_type;		/* type of filesystem */
	uint32_t	f_flags;	/* copy of mount exported flags */
	uint32_t	f_fssubtype;	/* fs sub-type (flavor) */
	char		f_fstypename[MFSTYPENAMELEN];
	char		f_mntonname[MAXPATHLEN];
	char		f_mntfromname[MAXPATHLEN];
	uint32_t	f_reserved[8];	/* for future use */
};

/* Mount flags (subset; values from xnu-3789.70.16 bsd/sys/mount.h). */
#define MNT_RDONLY	0x00000001
#define MNT_SYNCHRONOUS	0x00000002
#define MNT_NOEXEC	0x00000004
#define MNT_NOSUID	0x00000008
#define MNT_NODEV	0x00000010
#define MNT_UNION	0x00000020
#define MNT_ASYNC	0x00000040
#define MNT_CPROTECT	0x00000080
#define MNT_EXPORTED	0x00000100
#define MNT_QUARANTINE	0x00000200
#define MNT_LOCAL	0x00001000
#define MNT_QUOTA	0x00002000
#define MNT_ROOTFS	0x00004000
#define MNT_DOVOLFS	0x00008000
#define MNT_DONTBROWSE	0x00100000
#define MNT_IGNORE_OWNERSHIP 0x00200000
#define MNT_AUTOMOUNTED	0x00400000
#define MNT_JOURNALED	0x00800000
#define MNT_NOUSERXATTR	0x01000000
#define MNT_DEFWRITE	0x02000000
#define MNT_MULTILABEL	0x04000000
#define MNT_NOATIME	0x10000000
#define MNT_SNAPSHOT	0x40000000

/* getfsstat() flags */
#define MNT_WAIT	1	/* synchronized I/O file integrity completion */
#define MNT_NOWAIT	2	/* start all I/O, but do not wait for it */

__BEGIN_DECLS

int	getfsstat(struct statfs *, int, int);
int	getmntinfo(struct statfs **, int);
int	statfs(const char *, struct statfs *);
int	fstatfs(int, struct statfs *);
int	unmount(const char *, int);

__END_DECLS

#endif
