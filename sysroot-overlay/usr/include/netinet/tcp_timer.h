#ifndef _NETINET_TCP_TIMER_H_
#define _NETINET_TCP_TIMER_H_

/*
 * Minimal netinet/tcp_timer.h for the iOS armv7 cross build -- the
 * tcpsi_timer[] array in sys/proc_info.h's tcp_sockinfo is indexed by
 * these constants.  User-space values (BSD_KERNEL_PRIVATE branch of
 * xnu-3789.70.16 bsd/netinet/tcp_timer.h uses different numbers!).
 */

#define TCPT_REXMT	0	/* retransmit */
#define TCPT_PERSIST	1	/* retransmit persistence */
#define TCPT_KEEP	2	/* keep alive */
#define TCPT_2MSL	3	/* 2*msl quiet time timer */
#define TCPT_DELACK	4	/* delayed ack timer */
#define TCPT_MAX	4
#define TCPT_NONE	(TCPT_MAX + 1)
#define TCPT_NTIMERS	(TCPT_MAX + 1)

#endif
