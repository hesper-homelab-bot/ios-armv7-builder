/*
 * <sys/ioccom.h> for the iOS armv7 cross build, copied from
 * xnu-3789.70.16 bsd/sys/ioccom.h (Apple licence header elided; the body
 * defines the _IO/_IOR/_IOW/_IOWR request-code macros verbatim, with its
 * own include guard).
 */

#ifndef	_SYS_IOCCOM_H_
#define	_SYS_IOCCOM_H_

/* xnu includes <sys/_types.h> here, which is a kernel-internal header
 * pulling a tree of <sys/_types/*.h> files.  The _IO* macros below only
 * need the base integer types, so the sysroot's <sys/types.h> serves. */
#include <sys/types.h>

/*
 * Ioctl's have the command encoded in the lower word, and the size of
 * any in or out parameters in the upper word.  The high 3 bits of the
 * upper word are used to encode the in/out status of the parameter.
 */
#define	IOCPARM_MASK	0x1fff		/* parameter length, at most 13 bits */
#define	IOCPARM_LEN(x)	(((x) >> 16) & IOCPARM_MASK)
#define	IOCBASECMD(x)	((x) & ~(IOCPARM_MASK << 16))
#define	IOCGROUP(x)	(((x) >> 8) & 0xff)

#define	IOCPARM_MAX	(IOCPARM_MASK + 1)	/* max size of ioctl args */
				/* no parameters */
#define	IOC_VOID	(__uint32_t)0x20000000
				/* copy parameters out */
#define	IOC_OUT		(__uint32_t)0x40000000
				/* copy parameters in */
#define	IOC_IN		(__uint32_t)0x80000000
				/* copy paramters in and out */
#define	IOC_INOUT	(IOC_IN|IOC_OUT)
				/* mask for IN/OUT/VOID */
#define	IOC_DIRMASK	(__uint32_t)0xe0000000

#define	_IOC(inout,group,num,len) \
	(inout | ((len & IOCPARM_MASK) << 16) | ((group) << 8) | (num))
#define	_IO(g,n)	_IOC(IOC_VOID,	(g), (n), 0)
#define	_IOR(g,n,t)	_IOC(IOC_OUT,	(g), (n), sizeof(t))
#define	_IOW(g,n,t)	_IOC(IOC_IN,	(g), (n), sizeof(t))
/* this should be _IORW, but stdio got there first */
#define	_IOWR(g,n,t)	_IOC(IOC_INOUT,	(g), (n), sizeof(t))

#endif /* !_SYS_IOCCOM_H_ */
