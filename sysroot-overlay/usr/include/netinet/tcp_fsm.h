#ifndef _NETINET_TCP_FSM_H_
#define _NETINET_TCP_FSM_H_

/*
 * Minimal netinet/tcp_fsm.h for the iOS armv7 cross build: TCP state
 * numbering and (under TCPSTATES) the name table lsof's ptti.c prints.
 * Values verified against xnu-3789.70.16 bsd/netinet/tcp_fsm.h.
 */

#define TCP_NSTATES	11

#define TCPS_CLOSED		0	/* closed */
#define TCPS_LISTEN		1	/* listening for connection */
#define TCPS_SYN_SENT		2	/* active, have sent syn */
#define TCPS_SYN_RECEIVED	3	/* have sent and received syn */
#define TCPS_ESTABLISHED	4	/* established */
#define TCPS_CLOSE_WAIT		5	/* rcvd fin, waiting for close */
#define TCPS_FIN_WAIT_1		6	/* have closed, sent fin */
#define TCPS_CLOSING		7	/* closed xchd FIN; await FIN ACK */
#define TCPS_LAST_ACK		8	/* had fin and close; await FIN ACK */
#define TCPS_FIN_WAIT_2		9	/* have closed, fin is acked */
#define TCPS_TIME_WAIT		10	/* in 2*msl quiet wait after close */

#define TCP6_NSTATES		TCP_NSTATES
#define TCP6S_CLOSED		TCPS_CLOSED
#define TCP6S_LISTEN		TCPS_LISTEN
#define TCP6S_SYN_SENT		TCPS_SYN_SENT
#define TCP6S_SYN_RECEIVED	TCPS_SYN_RECEIVED
#define TCP6S_ESTABLISHED	TCPS_ESTABLISHED
#define TCP6S_CLOSE_WAIT	TCPS_CLOSE_WAIT
#define TCP6S_FIN_WAIT_1	TCPS_FIN_WAIT_1
#define TCP6S_CLOSING		TCPS_CLOSING
#define TCP6S_LAST_ACK		TCPS_LAST_ACK
#define TCP6S_FIN_WAIT_2	TCPS_FIN_WAIT_2
#define TCP6S_TIME_WAIT		TCPS_TIME_WAIT

#define TCPS_HAVERCVDSYN(s)	((s) >= TCPS_SYN_RECEIVED)
#define TCPS_HAVEESTABLISHED(s)	((s) >= TCPS_ESTABLISHED)
#define TCPS_HAVERCVDFIN(s)	((s) >= TCPS_TIME_WAIT)

#ifdef TCPSTATES
const char *tcpstates[] = {
	"CLOSED",	"LISTEN",	"SYN_SENT",	"SYN_RCVD",
	"ESTABLISHED",	"CLOSE_WAIT",	"FIN_WAIT_1",	"CLOSING",
	"LAST_ACK",	"FIN_WAIT_2",	"TIME_WAIT"
};
#endif

#endif
