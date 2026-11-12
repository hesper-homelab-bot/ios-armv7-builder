#ifndef _SYS_EVENT_H_
#define _SYS_EVENT_H_
/* Darwin kqueue interface, for the iOS armv7 cross build. */
#include <sys/types.h>
#include <stdint.h>

struct kevent {
	uintptr_t ident;
	int16_t   filter;
	uint16_t  flags;
	uint32_t  fflags;
	intptr_t  data;
	void     *udata;
};
/* [ios-armv7] sizeof(struct kevent) MUST stay 20: the iOS 10.3.3 (XNU 3248,
   armv7) kernel reads the 32-bit kevent ABI with 20-byte strides and NO
   ext[] tail.  A `uint64_t ext[4]` tail (52-byte stride) makes the kernel
   misparse every change after the first one as garbage: libuv/ares submit
   N>1 changelists and the kernel echoes the ext[] bytes back as bogus
   ident=0 EV_ERROR events (bad-fd aborts, SIGBUS; wall #14, 2026-11-11).
   Rule: multi-element runtime probes only -- a 1-change probe cannot
   detect a stride mismatch (the first element is always aligned). */

#define EV_SET(kevp, a, b, c, d, e, f) do {		\
	struct kevent *__kevp = (kevp);			\
	__kevp->ident  = (uintptr_t)(a);		\
	__kevp->filter = (int16_t)(b);			\
	__kevp->flags  = (uint16_t)(c);			\
	__kevp->fflags = (uint32_t)(d);			\
	__kevp->data   = (intptr_t)(e);			\
	__kevp->udata  = (void *)(f);			\
} while (0)

#define EVFILT_READ	(-1)
#define EVFILT_WRITE	(-2)
#define EVFILT_AIO	(-3)
#define EVFILT_VNODE	(-4)
#define EVFILT_PROC	(-5)
#define EVFILT_SIGNAL	(-6)
#define EVFILT_TIMER	(-7)
#define EVFILT_MACHPORT	(-8)
#define EVFILT_FS	(-9)
#define EVFILT_USER	(-10)
#define EVFILT_SYSCOUNT	17

#define EV_ADD		0x0001
#define EV_DELETE	0x0002
#define EV_ENABLE	0x0004
#define EV_DISABLE	0x0008
#define EV_ONESHOT	0x0010
#define EV_CLEAR	0x0020
#define EV_RECEIPT	0x0040
#define EV_DISPATCH	0x0080
#define EV_UDATA_SPECIFIC 0x0100
#define EV_FLAG1	0x2000
#define EV_ERROR	0x4000
#define EV_EOF		0x8000
#define EV_SYSFLAGS	0xF000

#define NOTE_LOWAT	0x0001
#define NOTE_DELETE	0x0001
#define NOTE_WRITE	0x0002
#define NOTE_EXTEND	0x0004
#define NOTE_ATTRIB	0x0008
#define NOTE_LINK	0x0010
#define NOTE_RENAME	0x0020
#define NOTE_REVOKE	0x0040
#define NOTE_EXIT	0x80000000
#define NOTE_FORK	0x40000000
#define NOTE_EXEC	0x20000000
#define NOTE_TRACK	0x00000001
/* The remaining Darwin NOTE_* flags.  nginx's kqueue module needs
   NOTE_TRIGGER for its EVFILT_USER notify path (ngx_kqueue_notify_init()),
   and without these the module does not compile at all.

   NOTE_TRIGGER is 0x01000000 on Darwin; this is NOT the Linux/FreeBSD
   value, and a wrong constant here is silent -- kevent() would simply never
   deliver the user event.  Verified on the device (iOS 10.3.3, XNU 3248
   armv7) with /tmp probe: EVFILT_USER EV_ADD, EVFILT_USER + 0x01000000,
   and the resulting wakeup all succeeded, with sizeof(struct kevent)==20. */
#define NOTE_TRIGGER	0x01000000
#define NOTE_FFNOP	0x00000000
#define NOTE_FFAND	0x40000000
#define NOTE_FFOR	0x80000000
#define NOTE_FFCOPY	0xc0000000
#define NOTE_FFCTRLMASK	0xc0000000
#define NOTE_FFLAGSMASK	0x00ffffff
#define NOTE_TRACKERR	0x00000002
#define NOTE_CHILD	0x00000004
#define NOTE_PCTRLMASK	0xf0000000
#define NOTE_PDATAMASK	0x000fffff
#define NOTE_EXITSTATUS	0x04000000
#define NOTE_REAP	0x10000000
#define NOTE_SIGNAL	0x08000000
#define NOTE_VM_PRESSURE	0x80000000
#define NOTE_VM_PRESSURE_TERMINATE	0x40000000
#define NOTE_VM_PRESSURE_SUDDEN_TERMINATE 0x20000000

int kqueue(void);
int kevent(int kq, const struct kevent *changelist, int nchanges,
    struct kevent *eventlist, int nevents, const struct timespec *timeout);

#endif
