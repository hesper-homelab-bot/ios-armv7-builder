
/* ===== DARWIN_OVERRIDES: Darwin socket constants =====
 * musl's numbers are Linux's.  The fatal one is SOL_SOCKET: Linux says 1,
 * Darwin says 0xffff, so a sendmsg() carrying an SCM_RIGHTS control message
 * (how tmux passes a tty fd to its server) fails with EINVAL.
 */
#undef SOL_SOCKET
#define SOL_SOCKET	0xffff
#undef SOL_LOCAL
#define SOL_LOCAL	0

#undef AF_UNSPEC
#define AF_UNSPEC	0
#undef AF_UNIX
#define AF_UNIX		1
#undef AF_LOCAL
#define AF_LOCAL	AF_UNIX
#undef AF_INET
#define AF_INET		2
#undef AF_ROUTE
#define AF_ROUTE	17
#undef AF_LINK
#define AF_LINK		18
#undef AF_INET6
#define AF_INET6	30
#undef AF_SYSTEM
#define AF_SYSTEM	32
#undef AF_MAX
#define AF_MAX		41
#undef PF_UNSPEC
#define PF_UNSPEC	AF_UNSPEC
#undef PF_UNIX
#define PF_UNIX		AF_UNIX
#undef PF_LOCAL
#define PF_LOCAL	AF_UNIX
#undef PF_INET
#define PF_INET		AF_INET
#undef PF_INET6
#define PF_INET6	AF_INET6

#undef SOCK_STREAM
#define SOCK_STREAM	1
#undef SOCK_DGRAM
#define SOCK_DGRAM	2
#undef SOCK_RAW
#define SOCK_RAW	3
#undef SOCK_RDM
#define SOCK_RDM	4
#undef SOCK_SEQPACKET
#define SOCK_SEQPACKET	5

#undef SO_DEBUG
#define SO_DEBUG	0x0001
#undef SO_ACCEPTCONN
#define SO_ACCEPTCONN	0x0002
#undef SO_REUSEADDR
#define SO_REUSEADDR	0x0004
#undef SO_KEEPALIVE
#define SO_KEEPALIVE	0x0008
#undef SO_DONTROUTE
#define SO_DONTROUTE	0x0010
#undef SO_BROADCAST
#define SO_BROADCAST	0x0020
#undef SO_USELOOPBACK
#define SO_USELOOPBACK	0x0040
#undef SO_LINGER
#define SO_LINGER	0x0080
#undef SO_OOBINLINE
#define SO_OOBINLINE	0x0100
#undef SO_REUSEPORT
#define SO_REUSEPORT	0x0200
#undef SO_TIMESTAMP
#define SO_TIMESTAMP	0x0400
#undef SO_SNDBUF
#define SO_SNDBUF	0x1001
#undef SO_RCVBUF
#define SO_RCVBUF	0x1002
#undef SO_SNDLOWAT
#define SO_SNDLOWAT	0x1003
#undef SO_RCVLOWAT
#define SO_RCVLOWAT	0x1004
#undef SO_SNDTIMEO
#define SO_SNDTIMEO	0x1005
#undef SO_RCVTIMEO
#define SO_RCVTIMEO	0x1006
#undef SO_ERROR
#define SO_ERROR	0x1007
#undef SO_TYPE
#define SO_TYPE		0x1008
#undef SO_NOSIGPIPE
#define SO_NOSIGPIPE	0x1022

#undef MSG_OOB
#define MSG_OOB		0x1
#undef MSG_PEEK
#define MSG_PEEK	0x2
#undef MSG_DONTROUTE
#define MSG_DONTROUTE	0x4
#undef MSG_EOR
#define MSG_EOR		0x8
#undef MSG_TRUNC
#define MSG_TRUNC	0x10
#undef MSG_CTRUNC
#define MSG_CTRUNC	0x20
#undef MSG_WAITALL
#define MSG_WAITALL	0x40
#undef MSG_DONTWAIT
#define MSG_DONTWAIT	0x80
#undef MSG_EOF
#define MSG_EOF		0x100
#undef MSG_NOSIGNAL
#define MSG_NOSIGNAL	0x80000

#undef SCM_RIGHTS
#define SCM_RIGHTS	0x01
#undef SCM_TIMESTAMP
#define SCM_TIMESTAMP	0x02
/* ===== end DARWIN_OVERRIDES ===== */
