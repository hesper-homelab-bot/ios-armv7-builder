/*
 * <sys/filio.h> for the iOS armv7 cross build, copied from xnu-3789.70.16
 * bsd/sys/filio.h (Apple licence header elided; the body is a list of
 * ioctl request codes, reproduced verbatim -- it carries its own include
 * guard, so no second guard is added here).
 *
 * Darwin split these out of <sys/ioctl.h>; BSD-targeted code includes it
 * explicitly (libuv's core.c, OpenSSL's sockets.h).
 */

#ifndef	_SYS_FILIO_H_
#define	_SYS_FILIO_H_

#include <sys/ioccom.h>

/* Generic file-descriptor ioctl's. */
#define	FIOCLEX		 _IO('f', 1)		/* set close on exec on fd */
#define	FIONCLEX	 _IO('f', 2)		/* remove close on exec */
#define	FIONREAD	_IOR('f', 127, int)	/* get # bytes to read */
#define	FIONBIO		_IOW('f', 126, int)	/* set/clear non-blocking i/o */
#define	FIOASYNC	_IOW('f', 125, int)	/* set/clear async i/o */
#define	FIOSETOWN	_IOW('f', 124, int)	/* set owner */
#define	FIOGETOWN	_IOR('f', 123, int)	/* get owner */
#define	FIODTYPE	_IOR('f', 122, int)	/* get d_type */

#ifdef KERNEL_PRIVATE
#define FIODEVICELOCKED	_IO('f', 121)	/* device locked/unlocked */
#define FIOPINSWAP		_IO('f', 120)	/* pin swap file to fast device */
#endif

#endif /* !_SYS_FILIO_H_ */
