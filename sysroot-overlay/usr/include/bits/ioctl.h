/* ioctl request constants for the armv7 iOS cross build.
 *
 * The _IO/_IOR/_IOW/_IOWR request-code macros are the BSD/XNU ones from
 * <sys/ioccom.h> (xnu-3789.70.16) -- musl's Linux-semantic versions encode
 * requests completely differently and silently produced wrong numbers for
 * every header that uses the macros (BIOCSETIF in <net/bpf.h> hit this:
 * nmap's libdnet could not bind en0).  If you ever need a genuinely Linux
 * request number, spell it as a literal -- none exist on this target.
 */
#include <sys/ioccom.h>

/* Darwin tty ioctl numbers (the values the iOS kernel actually answers;
 * probed via tmux on its pty and cross-checked against xnu). */
#define TIOCGWINSZ	0x40087468
#define TIOCSWINSZ	0x80087467
#define TIOCSCTTY	0x20007461
#define TIOCNOTTY	0x20007471
#define TIOCGPGRP	0x40047477
#define TIOCSPGRP	0x80047476
#define TIOCGETA	0x40487413
#define TIOCSETA	0x80487414
#define TIOCSETAW	0x80487415
#define TIOCSETAF	0x80487416
#define FIONREAD	0x4004667f
#define FIONBIO		0x8004667e
#define FIOASYNC	0x8004667d
#define TIOCEXCL	0x2000740d
#define TIOCNXCL	0x2000740e
#define TIOCPTYGRANT	0x20007454
#define TIOCPTYGNAME	0x40747453
#define TIOCPTYUNLK	0x20007452

/* modem bits: BSD values (same numbers Linux uses, kept for completeness) */
#define TIOCM_LE        0x001
#define TIOCM_DTR       0x002
#define TIOCM_RTS       0x004
#define TIOCM_ST        0x008
#define TIOCM_SR        0x010
#define TIOCM_CTS       0x020
#define TIOCM_CAR       0x040
#define TIOCM_RNG       0x080
#define TIOCM_DSR       0x100
#define TIOCM_CD        TIOCM_CAR
#define TIOCM_RI        TIOCM_RNG
#define TIOCM_OUT1      0x2000
#define TIOCM_OUT2      0x4000
#define TIOCM_LOOP      0x8000

/* SIOCGSTAMP / the 0x89xx Linux socket ioctls do not exist on Darwin and
 * have been removed: the routing/interface ioctls now live in
 * <sys/sockio.h> with their real BSD numbers. */

#include <bits/ioctl_fix.h>
