#ifndef _SYS_PARAM_H
#define _SYS_PARAM_H

/*
 * Darwin-flavoured sys/param.h for the iOS armv7 cross build.
 * Base is musl's sys/param.h; the differences that matter are:
 *
 *   * MAXPATHLEN is 1024 on Darwin (musl says 4096).  Kernel ABI structs
 *     embed char[MAXPATHLEN] arrays -- e.g. vnode_info_path in
 *     sys/proc_info.h -- so the value must match the kernel exactly.
 *   * MAXCOMLEN (16) is a Darwin define that sys/proc_info.h needs and
 *     musl does not provide.
 *
 * Verified against xnu-3789.70.16 (iOS 10.3.x).
 */

#define MAXSYMLINKS 20
#define MAXHOSTNAMELEN 64
#define MAXNAMLEN 255
#define MAXCOMLEN 16
#define MAXLOGNAME 255
#define MAXPATHLEN 1024
#define NBBY 8
#define NGROUPS 16	/* xnu syslimits.h: NGROUPS_MAX=16; _ucred embeds cr_groups[NGROUPS] */
#define CANBSIZ 255
#define NOFILE 256
#define NCARGS 131072
#define DEV_BSIZE 512
#define NOGROUP (-1)

#undef MIN
#undef MAX
#define MIN(a,b) (((a)<(b))?(a):(b))
#define MAX(a,b) (((a)>(b))?(a):(b))

#define __bitop(x,i,o) ((x)[(i)/8] o (1<<(i)%8))
#define setbit(x,i) __bitop(x,i,|=)
#define clrbit(x,i) __bitop(x,i,&=~)
#define isset(x,i) __bitop(x,i,&)
#define isclr(x,i) !isset(x,i)

#define howmany(n,d) (((n)+((d)-1))/(d))
#define roundup(n,d) (howmany(n,d)*(d))
#define powerof2(n) !(((n)-1) & (n))

#include <sys/resource.h>
#include <endian.h>
#include <limits.h>

#endif

/* ---- BSD IN_CLASS* address-classification macros (libpcap needs them;
 * 4.3BSD keeps them in <sys/param.h>, which is where pcap.c looks).  Pure
 * arithmetic on the address value -- no kernel ABI involved.  Values are
 * the universal 4.4BSD / XNU ones. ---- */
#include <sys/types.h>
#ifndef IN_CLASSA
#define IN_CLASSA(a)		((((in_addr_t)(a)) & 0x80000000) == 0)
#define IN_CLASSA_NET		0xff000000
#define IN_CLASSA_NSHIFT	24
#define IN_CLASSA_HOST		0x00ffffff
#define IN_CLASSA_MAX		128

#define IN_CLASSB(a)		((((in_addr_t)(a)) & 0xc0000000) == 0x80000000)
#define IN_CLASSB_NET		0xffff0000
#define IN_CLASSB_NSHIFT	16
#define IN_CLASSB_HOST		0x0000ffff
#define IN_CLASSB_MAX		65536

#define IN_CLASSC(a)		((((in_addr_t)(a)) & 0xe0000000) == 0xc0000000)
#define IN_CLASSC_NET		0xffffff00
#define IN_CLASSC_NSHIFT	8
#define IN_CLASSC_HOST		0x000000ff

#define IN_CLASSD(a)		((((in_addr_t)(a)) & 0xf0000000) == 0xe0000000)
#define IN_CLASSD_NET		0xf0000000
#define IN_MULTICAST(a)		IN_CLASSD(a)
#endif
