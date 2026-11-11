#ifndef _SYS_SYSCTL_H
#define _SYS_SYSCTL_H


#ifdef __cplusplus
extern "C" {
#endif

/*
 * Darwin sys/sysctl.h for the iOS armv7 cross build.
 *
 * Hand-adapted for user space from xnu-3789.70.16 (the open-source
 * release matching this device's xnu-3789.70.16~4 kernel).  Only the
 * parts a user-space program can actually observe are kept:
 *
 *   - the CTL_ top-level MIB names and the KERN_ / VM_ / HW_ / USER_
 *     subtree constants (identical values to the kernel's, since they
 *     are the wire format of the MIB array);
 *   - the KERN_PROC_ selector values;
 *   - struct kinfo_proc and its component structs, field for field.
 *
 * The struct layouts ARE kernel ABI: the kernel copies its own structs
 * into the caller's buffer, so a shifted field silently produces
 * garbage rather than an error.  (This is exactly what made lsof 4.78
 * useless on this device: it parsed an outdated struct kinfo_proc.)
 * Every field below is copied verbatim from the tag named above -- do
 * not "tidy" the layout.
 *
 * Deliberately NOT copied, because they are kernel-only machinery with
 * no user-space meaning:
 *   - the KERNEL / XNU_KERNEL_PRIVATE / BSD_KERNEL_PRIVATE blocks
 *     (struct sysctl_req, struct sysctl_oid, the SYSCTL_ linker-set
 *     declaration macros, the sysctl_register_ KPI);
 *   - the CTL_NAMES-style tables, which only sysctl(8) and the
 *     kernel's own MIB walkers consume;
 *   - the user64_ shadow structs, which are the kernel's in-kernel
 *     64-bit conversion helpers, never seen by a 32-bit client;
 *   - the kernel-internal sysctl names defined by other subsystem
 *     headers (socket.h, ipc.h, kdebug.h, ...).
 *
 * ONE IMPORTANT EXCEPTION -- ARMV7K PACKING.  On 32-bit ARM the kernel
 * does NOT hand userspace the natural user-space `struct kinfo_proc`.
 * bsd/kern/kern_sysctl.c calls proc_is64bit() on the *caller* and
 * copies out either user32_kinfo_proc or user64_kinfo_proc; for us it
 * is user32_kinfo_proc, and bsd/sys/proc_internal.h wraps its
 * user32_extern_proc in #pragma pack(4) with the explicit comment:
 *
 *   "This packing breaks symmetry with userspace side (struct
 *    extern_proc of proc.h) for the ARMV7K ABI where 64-bit types are
 *    64-bit aligned"
 *
 * So on armv7 the kernel's copy-out stride is the PACKED size, while a
 * naive user-space compiler lays the same fields out unpacked (u_quad_t
 * forced to 8-byte alignment) and gets a different, larger stride.  The
 * whole KERN_PROC_ALL array then decodes with every entry after the
 * first at the wrong offset.  We therefore apply the same #pragma
 * pack(4) around the struct definitions below, mirroring the kernel.
 *
 * Verified empirically on the iPad3,4 (xnu-3789.70.16~4): the sizing
 * call returns N*stride + 5*stride and the fetch returns N*stride; both
 * are exactly divisible by 492, and 492 is the packed size produced
 * below.  See the ARMV7K note above struct kinfo_proc.
 *
 * Type dependencies: the xnu header includes <sys/time.h> (for
 * struct timeval) and <sys/ucred.h>, and gets extern_proc from
 * <sys/proc.h> and vmspace from <sys/vm.h>.  Our sysroot has timeval
 * and rusage from the musl base tree, but has no Darwin proc.h /
 * vm.h / ucred.h -- so the handful of definitions actually needed are
 * inlined below, each marked with its origin.  See the notes on
 * struct ucred and struct vmspace, which are handled specially.
 */

#include <sys/types.h>
#include <sys/cdefs.h>
#include <sys/param.h>		/* MAXCOMLEN (NOT NGROUPS -- see below) */
#include <sys/time.h>		/* struct timeval, struct itimerval */

/*
 * Scalar typedefs the xnu structs below depend on, which this sysroot
 * does not otherwise provide.  All three come from xnu's own
 * bsd/sys/types.h (or, for boolean_t, mach/boolean.h) with identical
 * underlying types; each is guarded so that a future sysroot header
 * defining the real one wins without a redefinition error.
 *
 *   fixpt_t   - u_int32_t  (xnu bsd/sys/types.h) used by extern_proc
 *               AND by struct loadavg below.
 *   segsz_t   - int32_t    (xnu bsd/sys/types.h) used by eproc.e_xsize.
 *   boolean_t - int        (xnu osfmk/mach/boolean.h) used by
 *               extern_proc.sigwait and struct xsw_usage.xsu_encrypted.
 *
 * boolean_t is the odd one out: it is NOT in this sysroot at all, yet
 * the existing overlay header sys/proc_info.h already uses it in two
 * prototypes (workqueue_get_pwq_exceeded) and only compiles because
 * nothing has yet included that declaration after a definition.  It
 * really belongs in mach/machine.h (or a mach/boolean.h) alongside
 * integer_t; defining it here is the minimal local fix for this
 * header.  NOTE FOR THE SYSROOT OWNER: if boolean_t is later added to
 * mach/machine.h, this guard keeps that definition authoritative and
 * no change is needed here.
 */
#ifndef _FIXPT_T
#define _FIXPT_T
typedef u_int32_t fixpt_t;	/* fixed point number */
#endif

#ifndef _SEGSZ_T
#define _SEGSZ_T
typedef int32_t segsz_t;	/* segment size */
#endif

#ifndef _BOOLEAN_T
#define _BOOLEAN_T
typedef int boolean_t;
#endif

/*
 * dev_t is 32 bits on Darwin and 64 bits in musl, and eproc.e_tdev is a
 * dev_t embedded BY VALUE -- so the musl width shifts every later field
 * of struct kinfo_proc by 4 bytes (496 instead of 492).
 *
 *     xnu bsd/sys/_types.h:  typedef __int32_t __darwin_dev_t;
 *     xnu bsd/sys/_types/_dev_t.h:  typedef __darwin_dev_t dev_t;
 *
 * Our sysroot's sys/types.h already adopts Darwin's 32-bit *encoding*
 * via major()/minor()/makedev() before the end of the file, but it
 * leaves dev_t itself as musl's 64-bit type.  We must NOT redefine
 * dev_t globally here -- that would change every other struct in the
 * sysroot (stat, statfs, ...) as a side effect of including sysctl.h,
 * and several of those are already verified.  Instead the ABI structs
 * below use this explicitly-32-bit alias, which is what the kernel
 * puts on the wire.
 */
typedef int32_t sysctl_dev_t;	/* == Darwin dev_t (xnu _types.h) */

__BEGIN_DECLS

int	sysctl(int *, u_int, void *, size_t *, void *, size_t);
int	sysctlbyname(const char *, void *, size_t *, void *, size_t);
int	sysctlnametomib(const char *, int *, size_t *);

__END_DECLS

#define CTL_MAXNAME	12	/* largest number of components supported */

/*
 * struct ctlname is the type of the CTL_*_NAMES[] descriptor tables
 * that the kernel exposes via CTL_DEBUG.  Kept because it is cheap and
 * user-visible; the tables themselves are not.
 */
struct ctlname {
	char	*ctl_name;	/* subsystem name */
	int	ctl_type;	/* type of name */
};

#define CTLTYPE		0xf	/* Mask for the type */
#define	CTLTYPE_NODE	1	/* name is a node */
#define	CTLTYPE_INT	2	/* name describes an integer */
#define	CTLTYPE_STRING	3	/* name describes a string */
#define	CTLTYPE_QUAD	4	/* name describes a 64-bit number */
#define	CTLTYPE_OPAQUE	5	/* name describes a structure */
#define	CTLTYPE_STRUCT	CTLTYPE_OPAQUE	/* name describes a structure */

#define CTLFLAG_RD	0x80000000	/* Allow reads of variable */
#define CTLFLAG_WR	0x40000000	/* Allow writes to the variable */
#define CTLFLAG_RW	(CTLFLAG_RD|CTLFLAG_WR)
#define CTLFLAG_NOLOCK	0x20000000	/* XXX Don't Lock */
#define CTLFLAG_ANYBODY	0x10000000	/* All users can set this var */
#define CTLFLAG_SECURE	0x08000000	/* Permit set only if securelevel<=0 */
#define CTLFLAG_MASKED	0x04000000	/* deprecated variable, do not display */
#define CTLFLAG_NOAUTO	0x02000000	/* do not auto-register */
#define CTLFLAG_KERN	0x01000000	/* valid inside the kernel */
#define CTLFLAG_LOCKED	0x00800000	/* node will handle locking itself */
#define CTLFLAG_OID2	0x00400000	/* struct sysctl_oid has version info */

#define OID_AUTO	(-1)
#define OID_AUTO_START 100 /* conventional */

/*
 * Top-level identifiers
 */
#define	CTL_UNSPEC	0		/* unused */
#define	CTL_KERN	1		/* "high kernel": proc, limits */
#define	CTL_VM		2		/* virtual memory */
#define	CTL_VFS		3		/* file system, mount type is next */
#define	CTL_NET		4		/* network, see socket.h */
#define	CTL_DEBUG	5		/* debugging parameters */
#define	CTL_HW		6		/* generic cpu/io */
#define	CTL_MACHDEP	7		/* machine dependent */
#define	CTL_USER	8		/* user-level */
#define	CTL_MAXID	9		/* number of valid top-level ids */

/*
 * CTL_KERN identifiers
 */
#define	KERN_OSTYPE	 	 1	/* string: system version */
#define	KERN_OSRELEASE	 	 2	/* string: system release */
#define	KERN_OSREV	 	 3	/* int: system revision */
#define	KERN_VERSION	 	 4	/* string: compile time info */
#define	KERN_MAXVNODES	 	 5	/* int: max vnodes */
#define	KERN_MAXPROC	 	 6	/* int: max processes */
#define	KERN_MAXFILES	 	 7	/* int: max open files */
#define	KERN_ARGMAX	 	 8	/* int: max arguments to exec */
#define	KERN_SECURELVL	 	 9	/* int: system security level */
#define	KERN_HOSTNAME		10	/* string: hostname */
#define	KERN_HOSTID		11	/* int: host identifier */
#define	KERN_CLOCKRATE		12	/* struct: struct clockrate */
#define	KERN_VNODE		13	/* struct: vnode structures */
#define	KERN_PROC		14	/* struct: process entries */
#define	KERN_FILE		15	/* struct: file entries */
#define	KERN_PROF		16	/* node: kernel profiling info */
#define	KERN_POSIX1		17	/* int: POSIX.1 version */
#define	KERN_NGROUPS		18	/* int: # of supplemental group ids */
#define	KERN_JOB_CONTROL	19	/* int: is job control available */
#define	KERN_SAVED_IDS		20	/* int: saved set-user/group-ID */
#define	KERN_BOOTTIME		21	/* struct: time kernel was booted */
#define KERN_NISDOMAINNAME	22	/* string: YP domain name */
#define KERN_DOMAINNAME		KERN_NISDOMAINNAME
#define	KERN_MAXPARTITIONS	23	/* int: number of partitions/disk */
#define	KERN_KDEBUG		24	/* int: kernel trace points */
#define KERN_UPDATEINTERVAL	25	/* int: update process sleep time */
#define KERN_OSRELDATE		26	/* int: OS release date */
#define KERN_NTP_PLL		27	/* node: NTP PLL control */
#define	KERN_BOOTFILE		28	/* string: name of booted kernel */
#define	KERN_MAXFILESPERPROC	29	/* int: max open files per proc */
#define	KERN_MAXPROCPERUID 	30	/* int: max processes per uid */
#define KERN_DUMPDEV		31	/* dev_t: device to dump on */
#define	KERN_IPC		32	/* node: anything related to IPC */
#define	KERN_DUMMY		33	/* unused */
#define	KERN_PS_STRINGS		34	/* int: address of PS_STRINGS */
#define	KERN_USRSTACK32		35	/* int: address of USRSTACK */
#define	KERN_LOGSIGEXIT		36	/* int: do we log sigexit procs? */
#define KERN_SYMFILE		37	/* string: kernel symbol filename */
#define KERN_PROCARGS		38
#define KERN_NETBOOT		40	/* int: are we netbooted? 1=yes,0=no */
#define	KERN_SYSV		42	/* node: System V IPC information */
#define KERN_AFFINITY		43	/* xxx */
#define KERN_TRANSLATE	   	44	/* xxx */
#define KERN_CLASSIC	   	KERN_TRANSLATE	/* XXX backwards compat */
#define KERN_EXEC		45	/* xxx */
#define KERN_CLASSICHANDLER	KERN_EXEC /* XXX backwards compatibility */
#define	KERN_AIOMAX		46	/* int: max aio requests */
#define	KERN_AIOPROCMAX		47	/* int: max aio requests per process */
#define	KERN_AIOTHREADS		48	/* int: max aio worker threads */
#define	KERN_PROCARGS2		49	/* xnu guards this with __APPLE_API_UNSTABLE */
#define KERN_COREFILE		50	/* string: corefile format string */
#define KERN_COREDUMP		51	/* int: whether to coredump at all */
#define	KERN_SUGID_COREDUMP	52	/* int: whether to dump SUGID cores */
#define	KERN_PROCDELAYTERM	53	/* int: set/reset current proc for delayed termination during shutdown */
#define KERN_SHREG_PRIVATIZABLE	54	/* int: can shared regions be privatized ? */
#define	KERN_LOW_PRI_WINDOW	56	/* int: set/reset throttle window - milliseconds */
#define	KERN_LOW_PRI_DELAY	57	/* int: set/reset throttle delay - milliseconds */
#define	KERN_POSIX		58	/* node: posix tunables */
#define	KERN_USRSTACK64		59	/* LP64 user stack query */
#define KERN_NX_PROTECTION	60	/* int: whether no-execute protection is enabled */
#define	KERN_TFP 		61	/* Task for pid settings */
#define	KERN_PROCNAME 		62	/* setup process program  name(2*MAXCOMLEN) */
#define	KERN_THALTSTACK		63	/* for compat with older x86 and does nothing */
#define	KERN_SPECULATIVE_READS	64	/* int: whether speculative reads are disabled */
#define	KERN_OSVERSION		65	/* for build number i.e. 9A127 */
#define	KERN_SAFEBOOT		66	/* are we booted safe? */
#define KERN_RAGEVNODE		68
#define KERN_TTY		69	/* node: tty settings */
#define KERN_CHECKOPENEVT       70      /* spi: check the VOPENEVT flag on vnodes at open time */
#define	KERN_THREADNAME		71	/* set/get thread name */
#define	KERN_MAXID		72	/* number of valid kern ids */

#if defined(__LP64__)
#define	KERN_USRSTACK KERN_USRSTACK64
#else
#define	KERN_USRSTACK KERN_USRSTACK32
#endif

/* KERN_TFP types */
#define KERN_TFP_POLICY 		1
/* KERN_TFP_POLICY values . All policies allow task port for self */
#define KERN_TFP_POLICY_DENY 		0 	/* Deny Mode: None allowed except privileged */
#define KERN_TFP_POLICY_DEFAULT 	2	/* Default  Mode: related ones allowed and upcall authentication */

/*
 * KERN_PROC subtypes
 */
#define KERN_PROC_ALL		0	/* everything */
#define	KERN_PROC_PID		1	/* by process id */
#define	KERN_PROC_PGRP		2	/* by process group id */
#define	KERN_PROC_SESSION	3	/* by session of pid */
#define	KERN_PROC_TTY		4	/* by controlling tty */
#define	KERN_PROC_UID		5	/* by effective uid */
#define	KERN_PROC_RUID		6	/* by real uid */
#define	KERN_PROC_LCID		7	/* by login context id */

/*
 * struct extern_proc -- from xnu-3789.70.16 bsd/sys/proc.h.
 *
 * This is the user-visible prefix of struct proc.  The KERN_PROC_*
 * sysctls return struct kinfo_proc, which begins with this struct, so
 * its layout is ABI.
 *
 * p_un, p_forw/p_back and p_starttime are as in the xnu header.  The
 * union is what makes the first 8 bytes (on armv7) simultaneously a
 * two-pointer run-queue link and the process start time -- keep it.
 *
 * Only pointer-typed members appear here; they are 32-bit for the
 * armv7 ABI and 64-bit for an LP64 build, which is exactly what the
 * kernel does when it fills kinfo_proc for the caller's bitness.
 *
 * ARMV7K NOTE: on 32-bit ARM the kernel packs this to 4-byte alignment
 * (see the file header).  The #pragma below reproduces that, and is a
 * no-op on LP64, where pointers are naturally 8-byte aligned.  We use
 * push/pop so nothing outside this ABI region is affected.
 */
#pragma pack(push, 4)
struct extern_proc {
	union {
		struct {
			struct	proc *__p_forw;	/* Doubly-linked run/sleep queue. */
			struct	proc *__p_back;
		} p_st1;
		struct timeval __p_starttime; 	/* process start time */
	} p_un;
#define p_forw p_un.p_st1.__p_forw
#define p_back p_un.p_st1.__p_back
#define p_starttime p_un.__p_starttime
	struct	vmspace *p_vmspace;	/* Address space. */
	struct	sigacts *p_sigacts;	/* Signal actions, state (PROC ONLY). */
	int	p_flag;			/* P_* flags. */
	char	p_stat;			/* S* process status. */
	pid_t	p_pid;			/* Process identifier. */
	pid_t	p_oppid;	 /* Save parent pid during ptrace. XXX */
	int	p_dupfd;	 /* Sideways return value from fdopen. XXX */
	/* Mach related  */
	caddr_t user_stack;	/* where user stack was allocated */
	void	*exit_thread;	/* XXX Which thread is exiting? */
	int		p_debugger;		/* allow to debug */
	boolean_t	sigwait;	/* indication to suspend */
	/* scheduling */
	u_int	p_estcpu;	 /* Time averaged value of p_cpticks. */
	int	p_cpticks;	 /* Ticks of cpu time. */
	fixpt_t	p_pctcpu;	 /* %cpu for this process during p_swtime */
	void	*p_wchan;	 /* Sleep address. */
	char	*p_wmesg;	 /* Reason for sleep. */
	u_int	p_swtime;	 /* Time swapped in or out. */
	u_int	p_slptime;	 /* Time since last blocked. */
	struct	itimerval p_realtimer;	/* Alarm timer. */
	struct	timeval p_rtime;	/* Real time. */
	u_quad_t p_uticks;		/* Statclock hits in user mode. */
	u_quad_t p_sticks;		/* Statclock hits in system mode. */
	u_quad_t p_iticks;		/* Statclock hits processing intr. */
	int	p_traceflag;		/* Kernel trace points. */
	struct	vnode *p_tracep;	/* Trace to vnode. */
	int	p_siglist;		/* DEPRECATED. */
	struct	vnode *p_textvp;	/* Vnode of executable. */
	int	p_holdcnt;		/* If non-zero, don't swap. */
	sigset_t p_sigmask;	/* DEPRECATED. */
	sigset_t p_sigignore;	/* Signals being ignored. */
	sigset_t p_sigcatch;	/* Signals being caught by user. */
	u_char	p_priority;	/* Process priority. */
	u_char	p_usrpri;	/* User-priority based on p_cpu and p_nice. */
	char	p_nice;		/* Process "nice" value. */
	char	p_comm[MAXCOMLEN+1];
	struct 	pgrp *p_pgrp;	/* Pointer to process group. */
	struct	user *p_addr;	/* Kernel virtual addr of u-area (PROC ONLY). */
	u_short	p_xstat;	/* Exit status for wait; also stop signal. */
	u_short	p_acflag;	/* Accounting flags. */
	struct	rusage *p_ru;	/* Exit information. XXX */
};

/*
 * The KERN_PROC subtypes return arrays of augmented proc structures.
 *
 * struct _pcred / struct _ucred are from xnu-3789.70.16 bsd/sys/sysctl.h
 * itself (not from ucred.h -- note the leading underscore).  The
 * struct ucred that _pcred points to is only ever a pointer here, and
 * the kernel never dereferences it into the caller's buffer, so a
 * forward declaration is both sufficient and correct; this is why
 * sys/ucred.h is not needed.
 */
struct _pcred {
	char	pc_lock[72];		/* opaque content */
	struct	ucred *pc_ucred;	/* Current credentials. */
	uid_t	p_ruid;			/* Real user id. */
	uid_t	p_svuid;		/* Saved effective user id. */
	gid_t	p_rgid;			/* Real group id. */
	gid_t	p_svgid;		/* Saved effective group id. */
	int	p_refcnt;		/* Number of references. */
};

/*
 * NGROUPS SIZING -- this matters and must not come from sys/param.h.
 *
 * struct _ucred is embedded BY VALUE in eproc, so its size is part of
 * the kinfo_proc ABI.  cr_groups is dimensioned by NGROUPS, which xnu
 * defines as NGROUPS_MAX in bsd/sys/syslimits.h -- and there it is 16,
 * not 32:
 *
 *     bsd/sys/syslimits.h:  #define NGROUPS_MAX  16
 *     bsd/sys/param.h:      #define NGROUPS  NGROUPS_MAX
 *
 * Our sysroot's sys/param.h currently says `#define NGROUPS 32`,
 * which is wrong for this ABI.  Using it makes _ucred 140 instead of
 * 76 and struct kinfo_proc 556 instead of 492, which mis-strides the
 * KERN_PROC_ALL array.  We therefore use the xnu value directly here
 * rather than depending on the sysroot macro.  (See the note at the
 * end of this header about sys/param.h.)
 */
#define SYSCTL_NGROUPS 16	/* xnu bsd/sys/syslimits.h NGROUPS_MAX */

struct _ucred {
	int32_t	cr_ref;			/* reference count */
	uid_t	cr_uid;			/* effective user id */
	short	cr_ngroups;		/* number of groups */
	gid_t	cr_groups[SYSCTL_NGROUPS];	/* groups */
};

/*
 * struct vmspace -- from xnu-3789.70.16 bsd/sys/vm.h.
 *
 * IMPORTANT: this is the *opaque* user-space definition, not the real
 * kernel vmspace.  xnu defines it twice: the full machine-dependent
 * version under BSD_KERNEL_PRIVATE, and -- in the #else branch, with
 * the comment "just to keep kinfo_proc happy" -- this dummy of the
 * same size and pointer/non-pointer shape for everyone else.  We take
 * the second one, which is what a user-space compiler sees when it
 * includes the real xnu header.  It is embedded by value in kinfo_proc,
 * so its size is ABI even though its contents are not meaningful.
 */
struct vmspace {
	int32_t	dummy;
	caddr_t	dummy2;
	int32_t	dummy3[5];
	caddr_t	dummy4[3];
};

struct kinfo_proc {
	struct	extern_proc kp_proc;			/* proc structure */
	struct	eproc {
		struct	proc *e_paddr;		/* address of proc */
		struct	session *e_sess;	/* session pointer */
		struct	_pcred e_pcred;		/* process credentials */
		struct	_ucred e_ucred;		/* current credentials */
		struct	 vmspace e_vm;		/* address space */
		pid_t	e_ppid;			/* parent process id */
		pid_t	e_pgid;			/* process group id */
		short	e_jobc;			/* job control counter */
		sysctl_dev_t e_tdev;		/* controlling tty dev (Darwin dev_t = int32) */
		pid_t	e_tpgid;		/* tty process group id */
		struct	session *e_tsess;	/* tty session pointer */
#define	WMESGLEN	7
		char	e_wmesg[WMESGLEN+1];	/* wchan message */
		segsz_t e_xsize;		/* text size */
		short	e_xrssize;		/* text rss */
		short	e_xccount;		/* text references */
		short	e_xswrss;
		int32_t	e_flag;
#define	EPROC_CTTY	0x01	/* controlling tty vnode active */
#define	EPROC_SLEADER	0x02	/* session leader */
#define	COMAPT_MAXLOGNAME	12
		char	e_login[COMAPT_MAXLOGNAME];	/* short setlogin() name */
		int32_t	e_spare[4];
	} kp_eproc;
};
#pragma pack(pop)		/* end ARMV7K-packed ABI region */

/*
 * On the iPad3,4 this yields:
 *     sizeof(struct extern_proc) == 196
 *     sizeof(struct eproc)       == 296
 *     sizeof(struct kinfo_proc)  == 492
 * with kp_proc.p_pid at 24 and kp_proc.p_comm at 163.  492 was confirmed
 * against the running kernel: KERN_PROC_ALL sizing returned N*492 + 2460
 * (2460 == 5 * sizeof(struct kinfo_proc), the kernel's KERN_PROCSLOP) and
 * the fetch returned N*492.  A build that omits the pragma above gets 560
 * and mis-strides every entry after the first.
 */

/*
 * CTL_VM identifiers
 */
#define	VM_METER	1		/* struct vmmeter */
#define	VM_LOADAVG	2		/* struct loadavg */
#define	VM_MACHFACTOR	4		/* struct loadavg with mach factor*/
#define VM_SWAPUSAGE	5		/* total swap usage */
#define	VM_MAXID	6		/* number of valid vm ids */

struct xsw_usage {
	u_int64_t	xsu_total;
	u_int64_t	xsu_avail;
	u_int64_t	xsu_used;
	u_int32_t	xsu_pagesize;
	boolean_t	xsu_encrypted;
};

/*
 * struct loadavg is guarded by __APPLE_API_PRIVATE in xnu, i.e. it is
 * not part of the public API; VM_LOADAVG is still a documented
 * user-space query though, so the struct is kept here for callers that
 * read it directly.
 */
struct loadavg {
	fixpt_t	ldavg[3];
	long	fscale;
};
#define LSCALE	1000		/* scaling for "fixed point" arithmetic */

/*
 * CTL_HW identifiers
 */
#define	HW_MACHINE	 1		/* string: machine class */
#define	HW_MODEL	 2		/* string: specific machine model */
#define	HW_NCPU		 3		/* int: number of cpus */
#define	HW_BYTEORDER	 4		/* int: machine byte order */
#define	HW_PHYSMEM	 5		/* int: total memory */
#define	HW_USERMEM	 6		/* int: non-kernel memory */
#define	HW_PAGESIZE	 7		/* int: software page size */
#define	HW_DISKNAMES	 8		/* strings: disk drive names */
#define	HW_DISKSTATS	 9		/* struct: diskstats[] */
#define	HW_EPOCH  	10		/* int: 0 for Legacy, else NewWorld */
#define HW_FLOATINGPT	11		/* int: has HW floating point? */
#define HW_MACHINE_ARCH	12		/* string: machine architecture */
#define HW_VECTORUNIT	13		/* int: has HW vector unit? */
#define HW_BUS_FREQ	14		/* int: Bus Frequency */
#define HW_CPU_FREQ	15		/* int: CPU Frequency */
#define HW_CACHELINE	16		/* int: Cache Line Size in Bytes */
#define HW_L1ICACHESIZE	17		/* int: L1 I Cache Size in Bytes */
#define HW_L1DCACHESIZE	18		/* int: L1 D Cache Size in Bytes */
#define HW_L2SETTINGS	19		/* int: L2 Cache Settings */
#define HW_L2CACHESIZE	20		/* int: L2 Cache Size in Bytes */
#define HW_L3SETTINGS	21		/* int: L3 Cache Settings */
#define HW_L3CACHESIZE	22		/* int: L3 Cache Size in Bytes */
#define HW_TB_FREQ	23		/* int: Bus Frequency */
#define HW_MEMSIZE	24		/* uint64_t: physical ram size */
#define HW_AVAILCPU	25		/* int: number of available CPUs */
#define	HW_MAXID	26		/* number of valid hw ids */

/*
 * CTL_USER definitions
 */
#define	USER_CS_PATH		 1	/* string: _CS_PATH */
#define	USER_BC_BASE_MAX	 2	/* int: BC_BASE_MAX */
#define	USER_BC_DIM_MAX		 3	/* int: BC_DIM_MAX */
#define	USER_BC_SCALE_MAX	 4	/* int: BC_SCALE_MAX */
#define	USER_BC_STRING_MAX	 5	/* int: BC_STRING_MAX */
#define	USER_COLL_WEIGHTS_MAX	 6	/* int: COLL_WEIGHTS_MAX */
#define	USER_EXPR_NEST_MAX	 7	/* int: EXPR_NEST_MAX */
#define	USER_LINE_MAX		 8	/* int: LINE_MAX */
#define	USER_RE_DUP_MAX		 9	/* int: RE_DUP_MAX */
#define	USER_POSIX2_VERSION	10	/* int: POSIX2_VERSION */
#define	USER_POSIX2_C_BIND	11	/* int: POSIX2_C_BIND */
#define	USER_POSIX2_C_DEV	12	/* int: POSIX2_C_DEV */
#define	USER_POSIX2_CHAR_TERM	13	/* int: POSIX2_CHAR_TERM */
#define	USER_POSIX2_FORT_DEV	14	/* int: POSIX2_FORT_DEV */
#define	USER_POSIX2_FORT_RUN	15	/* int: POSIX2_FORT_RUN */
#define	USER_POSIX2_LOCALEDEF	16	/* int: POSIX2_LOCALEDEF */
#define	USER_POSIX2_SW_DEV	17	/* int: POSIX2_SW_DEV */
#define	USER_POSIX2_UPE		18	/* int: POSIX2_UPE */
#define	USER_STREAM_MAX		19	/* int: POSIX2_STREAM_MAX */
#define	USER_TZNAME_MAX		20	/* int: POSIX2_TZNAME_MAX */
#define	USER_MAXID		21	/* number of valid user ids */

/*
 * CTL_DEBUG definitions
 *
 * Second level identifier specifies which debug variable.
 * Third level identifier specifies which stucture component.
 */
#define	CTL_DEBUG_NAME		0	/* string: variable name */
#define	CTL_DEBUG_VALUE		1	/* int: variable value */
#define	CTL_DEBUG_MAXID		20

/*
 * xnu asserts that these ids have not drifted.  Kept so that a future
 * update of this header against a newer xnu tag fails loudly instead of
 * silently changing the ABI.  Not an #error on anything we deliberately
 * omitted: the check exists to catch *ourselves* getting a value wrong.
 */
#if (CTL_MAXID != 9) || (KERN_MAXID != 72) || (VM_MAXID != 6) || (HW_MAXID != 26) || (USER_MAXID != 21) || (CTL_DEBUG_MAXID != 20)
#error "sysctl id drift vs xnu-3789.70.16"
#endif

/*
 * Compile-time guard on the ARMV7K struct sizes.  These are not style
 * preferences: they are what the running kernel copies out, and the
 * device measurement that pins 492 is described in the file header.
 * If this fires, do not "fix" the numbers -- re-derive them against the
 * kernel (KERN_PROC_ALL sizing returns N*size + 5*size) before
 * touching anything.
 */
#if !defined(__LP64__)
_Static_assert(sizeof(struct kinfo_proc) == 492, "armv7 kinfo_proc must be 492 (ARMV7K packed)");
_Static_assert(__builtin_offsetof(struct kinfo_proc, kp_proc.p_pid) == 24, "armv7 p_pid offset");
_Static_assert(__builtin_offsetof(struct kinfo_proc, kp_proc.p_comm) == 163, "armv7 p_comm offset");
#endif

/*
 * NOTES FOR THE SYSROOT OWNER -- two pre-existing bugs this header
 * works around locally rather than fixing, because fixing them changes
 * types that other, already-verified overlay headers depend on:
 *
 *   1. sys/param.h defines `NGROUPS 32`.  xnu defines
 *      NGROUPS as NGROUPS_MAX in bsd/sys/syslimits.h, and there it is
 *      16.  struct _ucred embeds gid_t cr_groups[NGROUPS] by value, so
 *      this makes struct kinfo_proc 556 instead of 492.  This header
 *      uses its own SYSCTL_NGROUPS (16) and does not consume NGROUPS.
 *      Consider correcting sys/param.h to 16.
 *
 *   2. sys/types.h adopts Darwin's 32-bit dev_t *encoding* through
 *      major()/minor()/makedev(), but dev_t itself is still musl's
 *      64-bit type, whereas Darwin's dev_t is __int32_t.  Any ABI
 *      struct embedding a dev_t by value is therefore oversized.  This
 *      header uses sysctl_dev_t (int32_t) for e_tdev.  Widening this
 *      fix into sys/types.h would need every other dev_t-embedding
 *      struct (stat, statfs, ...) re-verified.
 *
 * Both were found by diffing this header's struct sizes against the
 * live kernel's KERN_PROC_ALL stride, not by reading the sources.
 */


#ifdef __cplusplus
}
#endif

#endif /* _SYS_SYSCTL_H */
