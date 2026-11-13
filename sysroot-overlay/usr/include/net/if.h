#ifndef _NET_IF_H
#define _NET_IF_H

#ifdef __cplusplus
extern "C" {
#endif

#include <features.h>

#define IF_NAMESIZE 16

struct if_nameindex {
	unsigned int if_index;
	char *if_name;
};

unsigned int if_nametoindex (const char *);
char *if_indextoname (unsigned int, char *);
struct if_nameindex *if_nameindex (void);
void if_freenameindex (struct if_nameindex *);




#if defined(_GNU_SOURCE) || defined(_BSD_SOURCE)

#include <sys/socket.h>

#define IFF_UP	0x1
#define IFF_BROADCAST 0x2
#define IFF_DEBUG 0x4
#define IFF_LOOPBACK 0x8
#define IFF_POINTOPOINT 0x10
#define IFF_NOTRAILERS 0x20
#define IFF_RUNNING 0x40
#define IFF_NOARP 0x80
#define IFF_PROMISC 0x100
#define IFF_ALLMULTI 0x200
#define IFF_MASTER 0x400
#define IFF_SLAVE 0x800
#define IFF_MULTICAST 0x1000
#define IFF_PORTSEL 0x2000
#define IFF_AUTOMEDIA 0x4000
#define IFF_DYNAMIC 0x8000
#define IFF_LOWER_UP 0x10000
#define IFF_DORMANT 0x20000
#define IFF_ECHO 0x40000
#define IFF_VOLATILE (IFF_LOOPBACK|IFF_POINTOPOINT|IFF_BROADCAST| \
        IFF_ECHO|IFF_MASTER|IFF_SLAVE|IFF_RUNNING|IFF_LOWER_UP|IFF_DORMANT)

struct ifaddr {
	struct sockaddr ifa_addr;
	union {
		struct sockaddr	ifu_broadaddr;
		struct sockaddr	ifu_dstaddr;
	} ifa_ifu;
	struct iface *ifa_ifp;
	struct ifaddr *ifa_next;
};

#define ifa_broadaddr	ifa_ifu.ifu_broadaddr
#define ifa_dstaddr	ifa_ifu.ifu_dstaddr

struct ifmap {
	unsigned long int mem_start;
	unsigned long int mem_end;
	unsigned short int base_addr;
	unsigned char irq;
	unsigned char dma;
	unsigned char port;
};

#define IFHWADDRLEN	6
#define IFNAMSIZ	IF_NAMESIZE

struct ifreq {
	union {
		char ifrn_name[IFNAMSIZ];
	} ifr_ifrn;
	union {
		struct sockaddr ifru_addr;
		struct sockaddr ifru_dstaddr;
		struct sockaddr ifru_broadaddr;
		struct sockaddr ifru_netmask;
		struct sockaddr ifru_hwaddr;
		short int ifru_flags;
		int ifru_ivalue;
		int ifru_mtu;
		struct ifmap ifru_map;
		char ifru_slave[IFNAMSIZ];
		char ifru_newname[IFNAMSIZ];
		char *ifru_data;
	} ifr_ifru;
};

#define ifr_name	ifr_ifrn.ifrn_name
#define ifr_hwaddr	ifr_ifru.ifru_hwaddr
#define ifr_addr	ifr_ifru.ifru_addr
#define ifr_dstaddr	ifr_ifru.ifru_dstaddr
#define ifr_broadaddr	ifr_ifru.ifru_broadaddr
#define ifr_netmask	ifr_ifru.ifru_netmask
#define ifr_flags	ifr_ifru.ifru_flags
#define ifr_metric	ifr_ifru.ifru_ivalue
#define ifr_mtu		ifr_ifru.ifru_mtu
#define ifr_map		ifr_ifru.ifru_map
#define ifr_slave	ifr_ifru.ifru_slave
#define ifr_data	ifr_ifru.ifru_data
#define ifr_ifindex	ifr_ifru.ifru_ivalue
#define ifr_bandwidth	ifr_ifru.ifru_ivalue
#define ifr_qlen	ifr_ifru.ifru_ivalue
#define ifr_newname	ifr_ifru.ifru_newname
#define _IOT_ifreq	_IOT(_IOTS(char),IFNAMSIZ,_IOTS(char),16,0,0)
#define _IOT_ifreq_short _IOT(_IOTS(char),IFNAMSIZ,_IOTS(short),1,0,0)
#define _IOT_ifreq_int	_IOT(_IOTS(char),IFNAMSIZ,_IOTS(int),1,0,0)

struct ifconf {
	int ifc_len;		
	union {
		char *ifcu_buf;
		struct ifreq *ifcu_req;
	} ifc_ifcu;
};

#define ifc_buf		ifc_ifcu.ifcu_buf
#define ifc_req		ifc_ifcu.ifcu_req
#define _IOT_ifconf _IOT(_IOTS(struct ifconf),1,0,0,0,0)

#define __UAPI_DEF_IF_IFCONF                                    0
#define __UAPI_DEF_IF_IFMAP                                     0
#define __UAPI_DEF_IF_IFNAMSIZ                                  0
#define __UAPI_DEF_IF_IFREQ                                     0
#define __UAPI_DEF_IF_NET_DEVICE_FLAGS                          0
#define __UAPI_DEF_IF_NET_DEVICE_FLAGS_LOWER_UP_DORMANT_ECHO    0

#endif

#ifdef __cplusplus
}
#endif

#endif

/* ---- Darwin-only interface ioctls reference these; musl's if.h lacks
 * them (values/shape from xnu-3789.70.16 bsd/net/if.h; IFNAMSIZ is 16 in
 * both).  sockio.h's SIOCAIFADDR does sizeof(struct ifaliasreq). ---- */
#ifndef _NET_IF_H_IFALIASREQ
#define _NET_IF_H_IFALIASREQ
struct ifaliasreq {
	char	ifra_name[IFNAMSIZ];
	struct	sockaddr ifra_addr;
	struct	sockaddr ifra_broadaddr;
	struct	sockaddr ifra_mask;
};
#endif


/* ---- routing-socket message structures (from xnu-3789.70.16; libdnet
 * eth-bsd.c walks NET_RT_IFLIST messages built from these).  On this 32-bit
 * target IF_DATA_TIMEVAL is timeval32 (see sys/_types/_timeval32.h). ---- */
#ifndef _NET_IF_H_MSGHDR
#define _NET_IF_H_MSGHDR
#include <sys/_types/_timeval32.h>
#define IF_DATA_TIMEVAL timeval32
struct if_data64 {
	/* generic interface information */
	u_char		ifi_type;		/* ethernet, tokenring, etc */
	u_char		ifi_typelen;		/* Length of frame type id */
	u_char		ifi_physical;		/* e.g., AUI, Thinnet, 10base-T, etc */
	u_char		ifi_addrlen;		/* media address length */
	u_char		ifi_hdrlen;		/* media header length */
	u_char		ifi_recvquota;		/* polling quota for receive intrs */
	u_char		ifi_xmitquota;		/* polling quota for xmit intrs */
	u_char		ifi_unused1;		/* for future use */
	u_int32_t	ifi_mtu;		/* maximum transmission unit */
	u_int32_t	ifi_metric;		/* routing metric (external only) */
	u_int64_t	ifi_baudrate;		/* linespeed */
	/* volatile statistics */
	u_int64_t	ifi_ipackets;		/* packets received on interface */
	u_int64_t	ifi_ierrors;		/* input errors on interface */
	u_int64_t	ifi_opackets;		/* packets sent on interface */
	u_int64_t	ifi_oerrors;		/* output errors on interface */
	u_int64_t	ifi_collisions;		/* collisions on csma interfaces */
	u_int64_t	ifi_ibytes;		/* total number of octets received */
	u_int64_t	ifi_obytes;		/* total number of octets sent */
	u_int64_t	ifi_imcasts;		/* packets received via multicast */
	u_int64_t	ifi_omcasts;		/* packets sent via multicast */
	u_int64_t	ifi_iqdrops;		/* dropped on input, this interface */
	u_int64_t	ifi_noproto;		/* destined for unsupported protocol */
	u_int32_t	ifi_recvtiming;		/* usec spent receiving when timing */
	u_int32_t	ifi_xmittiming;		/* usec spent xmitting when timing */
	struct IF_DATA_TIMEVAL ifi_lastchange;	/* time of last administrative change */
};

#endif
struct if_data {
	/* generic interface information */
	u_char		ifi_type;	/* ethernet, tokenring, etc */
	u_char		ifi_typelen;	/* Length of frame type id */
	u_char		ifi_physical;	/* e.g., AUI, Thinnet, 10base-T, etc */
	u_char		ifi_addrlen;	/* media address length */
	u_char		ifi_hdrlen;	/* media header length */
	u_char		ifi_recvquota;	/* polling quota for receive intrs */
	u_char		ifi_xmitquota;	/* polling quota for xmit intrs */
	u_char		ifi_unused1;	/* for future use */
	u_int32_t	ifi_mtu;	/* maximum transmission unit */
	u_int32_t	ifi_metric;	/* routing metric (external only) */
	u_int32_t	ifi_baudrate;	/* linespeed */
	/* volatile statistics */
	u_int32_t	ifi_ipackets;	/* packets received on interface */
	u_int32_t	ifi_ierrors;	/* input errors on interface */
	u_int32_t	ifi_opackets;	/* packets sent on interface */
	u_int32_t	ifi_oerrors;	/* output errors on interface */
	u_int32_t	ifi_collisions;	/* collisions on csma interfaces */
	u_int32_t	ifi_ibytes;	/* total number of octets received */
	u_int32_t	ifi_obytes;	/* total number of octets sent */
	u_int32_t	ifi_imcasts;	/* packets received via multicast */
	u_int32_t	ifi_omcasts;	/* packets sent via multicast */
	u_int32_t	ifi_iqdrops;	/* dropped on input, this interface */
	u_int32_t	ifi_noproto;	/* destined for unsupported protocol */
	u_int32_t	ifi_recvtiming;	/* usec spent receiving when timing */
	u_int32_t	ifi_xmittiming;	/* usec spent xmitting when timing */
	struct IF_DATA_TIMEVAL ifi_lastchange;	/* time of last administrative change */
	u_int32_t	ifi_unused2;	/* used to be the default_proto */
	u_int32_t	ifi_hwassist;	/* HW offload capabilities */
	u_int32_t	ifi_reserved1;	/* for future use */
	u_int32_t	ifi_reserved2;	/* for future use */
};
struct if_msghdr {
	unsigned short	ifm_msglen;	/* to skip non-understood messages */
	unsigned char	ifm_version;	/* future binary compatability */
	unsigned char	ifm_type;	/* message type */
	int		ifm_addrs;	/* like rtm_addrs */
	int		ifm_flags;	/* value of if_flags */
	unsigned short	ifm_index;	/* index for associated ifp */
	struct	if_data ifm_data;	/* statistics and other data about if */
};

struct if_msghdr2 {
	u_short	ifm_msglen;	/* to skip over non-understood messages */
	u_char	ifm_version;	/* future binary compatability */
	u_char	ifm_type;	/* message type */
	int	ifm_addrs;	/* like rtm_addrs */
	int	ifm_flags;	/* value of if_flags */
	u_short	ifm_index;	/* index for associated ifp */
	int	ifm_snd_len;	/* instantaneous length of send queue */
	int	ifm_snd_maxlen;	/* maximum length of send queue */
	int	ifm_snd_drops;	/* number of drops in send queue */
	int	ifm_timer;	/* time until if_watchdog called */
	struct if_data64	ifm_data;	/* statistics and other data */
};

/* ---- from xnu-3789.70.16 bsd/net/if.h (verbatim; no trailing ifam_data
 * on this kernel -- rtsock.c fills only the 7 fields below).  Emitted by
 * NET_RT_IFLIST/IFLIST2 as RTM_NEWADDR after each if_msghdr[2]; its
 * sockaddrs (RTA_IFP/IFP sockaddr_dl with the interface name, RTA_IFA,
 * RTA_NETMASK, RTA_BRD) follow inside ifam_msglen.  Consumed by
 * netstat's -i and ifmap building. [device-verified 2026-11-13] ---- */
struct ifa_msghdr {
	unsigned short	ifam_msglen;	/* to skip non-understood messages */
	unsigned char	ifam_version;	/* future binary compatability */
	unsigned char	ifam_type;	/* message type */
	int		ifam_addrs;	/* like rtm_addrs */
	int		ifam_flags;	/* value of ifa_flags */
	unsigned short	ifam_index;	/* index for associated ifp */
	int		ifam_metric;	/* value of ifa_metric */
};
