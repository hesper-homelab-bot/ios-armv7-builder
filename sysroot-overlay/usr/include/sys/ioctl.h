#ifndef	_SYS_IOCTL_H
#define	_SYS_IOCTL_H
#ifdef __cplusplus
extern "C" {
#endif

#define __NEED_struct_winsize

#include <bits/alltypes.h>
#include <bits/ioctl.h>

#define N_TTY           0
#define N_SLIP          1
#define N_MOUSE         2
#define N_PPP           3
#define N_STRIP         4
#define N_AX25          5
#define N_X25           6
#define N_6PACK         7
#define N_MASC          8
#define N_R3964         9
#define N_PROFIBUS_FDL  10
#define N_IRDA          11
#define N_SMSBLOCK      12
#define N_HDLC          13
#define N_SYNC_PPP      14
#define N_HCI           15
#define N_GIGASET_M101  16
#define N_SLCAN         17
#define N_PPS           18
#define N_V253          19
#define N_CAIF          20
#define N_GSM0710       21
#define N_TI_WL         22
#define N_TRACESINK     23
#define N_TRACEROUTER   24
#define N_NCI           25
#define N_SPEAKUP       26
#define N_NULL          27

#define TIOCPKT_DATA       0
#define TIOCPKT_FLUSHREAD  1
#define TIOCPKT_FLUSHWRITE 2
#define TIOCPKT_STOP       4
#define TIOCPKT_START      8
#define TIOCPKT_NOSTOP    16
#define TIOCPKT_DOSTOP    32
#define TIOCPKT_IOCTL     64

#define TIOCSER_TEMT 1

/* NOTE: the Linux SIOC* block (SIOCGIFCONF 0x8912 et al) that musl had
 * here has been removed: those request numbers are meaningless on Darwin
 * and masked the real BSD ones that sys/sockio.h now provides (libdnet's
 * SIOCGIFCONF on a Linux value silently returned nothing on the device). */

int ioctl (int, int, ...);

/*
 * fsctl() is Darwin's filesystem-specific ioctl entry point.  libuv's
 * darwin.c calls it (F_PUNCHHOLE / F_TRIM_ACTIVE_FILE handling); the
 * symbol is exported by libSystem.
 */
int fsctl(const char *path, unsigned long request, void *data, unsigned options);
int ffsctl(int fd, unsigned long request, void *data, unsigned options);

#ifdef __cplusplus
}
#endif

/* ===== DARWIN_OVERRIDES: Darwin ioctl numbers =====
 * The Linux numbers (0x54xx) are meaningless to the iOS kernel; tmux asks for
 * the window size on its pty, so these have to be right.
 */
#undef TIOCGWINSZ
#define TIOCGWINSZ	0x40087468
#undef TIOCSWINSZ
#define TIOCSWINSZ	0x80087467
#undef TIOCSCTTY
#define TIOCSCTTY	0x20007461
#undef TIOCNOTTY
#define TIOCNOTTY	0x20007471
#undef TIOCGPGRP
#define TIOCGPGRP	0x40047477
#undef TIOCSPGRP
#define TIOCSPGRP	0x80047476
#undef TIOCGETA
#define TIOCGETA	0x40487413
#undef TIOCSETA
#define TIOCSETA	0x80487414
#undef TIOCSETAW
#define TIOCSETAW	0x80487415
#undef TIOCSETAF
#define TIOCSETAF	0x80487416
#undef FIONREAD
#define FIONREAD	0x4004667f
#undef FIONBIO
#define FIONBIO		0x8004667e
#undef TIOCEXCL
#define TIOCEXCL	0x2000740d
#undef TIOCNXCL
#define TIOCNXCL	0x2000740e

/*
 * pty allocation ioctls: libuv's tty.c probes a descriptor with
 * TIOCPTYGNAME to decide whether it is a pty master.
 *
 * Values follow from xnu-3789.70.16 bsd/sys/ttycom.h, which spells them
 * with the _IO/_IOC macros (see <sys/ioccom.h>):
 *
 *   #define TIOCPTYGRANT  _IO('t', 84)                -> 0x20007454
 *   #define TIOCPTYGNAME  _IOC(IOC_OUT, 't', 83, 128) -> 0x40747453
 *   #define TIOCPTYUNLK   _IO('t', 82)                -> 0x20007452
 *
 * 't' = 0x74; _IO is 0x20000000 | num in the low byte with 0x74<<8, while
 * _IOC_OUT adds 0x40000000 and puts the 128-byte payload in the size field.
 */
#undef TIOCPTYGRANT
#define TIOCPTYGRANT	0x20007454
#undef TIOCPTYGNAME
#define TIOCPTYGNAME	0x40747453
#undef TIOCPTYUNLK
#define TIOCPTYUNLK	0x20007452
/* ===== end DARWIN_OVERRIDES ===== */
#endif
