#ifndef _LIBPROC_H_
#define _LIBPROC_H_
/* Minimal libproc.h for cross-compiling tmux against iOS 10.3 (armv7). */
#include <sys/types.h>
#include <Availability.h>

#ifndef MAXCOMLEN
#define MAXCOMLEN 16
#endif
#ifndef MAXPATHLEN
#define MAXPATHLEN 1024
#endif

typedef union { int32_t val[2]; } fsid_t;

struct vinfo_stat {
	uint32_t vst_dev;
	uint16_t vst_mode;
	uint16_t vst_nlink;
	uint64_t vst_ino;
	uid_t    vst_uid;
	gid_t    vst_gid;
	int64_t  vst_atime;
	int64_t  vst_atimensec;
	int64_t  vst_mtime;
	int64_t  vst_mtimensec;
	int64_t  vst_ctime;
	int64_t  vst_ctimensec;
	int64_t  vst_birthtime;
	int64_t  vst_birthtimensec;
	int64_t  vst_size;
	int64_t  vst_blocks;
	int32_t  vst_blksize;
	uint32_t vst_flags;
	uint32_t vst_gen;
	uint32_t vst_rdev;
	int64_t  vst_qspare[2];
};

struct vnode_info { struct vinfo_stat vi_stat; int vi_type; int vi_pad; fsid_t vi_fsid; };
struct vnode_info_path { struct vnode_info vip_vi; char vip_path[MAXPATHLEN]; };
struct proc_vnodepathinfo { struct vnode_info_path pvi_cdir; struct vnode_info_path pvi_rdir; };

struct proc_bsdinfo {
	uint32_t pbi_flags;
	uint32_t pbi_status;
	uint32_t pbi_xstatus;
	uint32_t pbi_pid;
	uint32_t pbi_ppid;
	uid_t    pbi_uid;
	gid_t    pbi_gid;
	uid_t    pbi_ruid;
	gid_t    pbi_rgid;
	uid_t    pbi_svuid;
	gid_t    pbi_svgid;
	uint32_t rfu_1;
	char     pbi_comm[MAXCOMLEN];
	char     pbi_name[2*MAXCOMLEN];
	uint32_t pbi_nfiles;
	uint32_t pbi_pgid;
	uint32_t pbi_pjobc;
	uint32_t e_tdev;
	uint32_t e_tpgid;
	int32_t  pbi_nice;
};

struct proc_bsdshortinfo {
	uint32_t pbsi_pid;
	uint32_t pbsi_ppid;
	uint32_t pbsi_pgid;
	uint32_t pbsi_status;
	char     pbsi_comm[MAXCOMLEN];
	uint32_t pbsi_flags;
	uid_t    pbsi_uid;
	gid_t    pbsi_gid;
	uint32_t pbsi_ruid;
	uint32_t pbsi_rgid;
	uint32_t pbsi_svuid;
	uint32_t pbsi_svgid;
	uint32_t pbsi_rfu;
};

struct proc_fdinfo {
	int32_t	proc_fd;
	uint32_t proc_fdtype;
};

#define PROC_PIDLISTFDS		1
#define PROC_PIDLISTFD_SIZE	((int)sizeof(struct proc_fdinfo))
#define PROC_PIDT_SHORTBSDINFO  3
#define PROC_PIDVNODEPATHINFO   9
#define PROC_PIDTBSDINFO        1

int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);
int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
#endif
