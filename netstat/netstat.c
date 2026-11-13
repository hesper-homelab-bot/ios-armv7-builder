/*
 * netstat for armv7 iOS 10.3.3 (iPad3,4, xnu-3789.70.16).
 *
 * The kernel sysctls this reads are the same ones macOS netstat reads:
 *   net.inet.tcp.pcblist / net.inet.udp.pcblist / net.inet.raw.pcblist
 *   NET_RT_DUMP (routes) / NET_RT_IFLIST2|IFLIST (interfaces)
 *
 * WHY HAND-ROLLED STRUCTS: the sysctl payloads embed kernel structs
 * (struct inpcb userland form, struct xsocket, struct otcpcb) whose
 * headers are not public on iOS.  Apple's own netstat duplicates them
 * too.  Every offset here was MEASURED on the device (probes in
 * ~/scratch/netstat/, 2026-11-13) and cross-checked against lsof:
 *
 *   buffer layout: [xinpgen 24B][entries...][xinpgen trailer 24B]
 *     xinpgen 24B : xig_len@0 xig_count@4 xig_gen@8 xig_sogen@16
 *     tcp entry 524B (struct xtcpcb): xt_len@0, inpcb@4, otcpcb@212,
 *                                     xsocket@416, alignhack@516
 *     udp/raw entry 320B (struct xinpcb): xi_len@0, inpcb@4, xsocket@212
 *   inside struct inpcb (208B @4):
 *     inp_fport@20 inp_lport@22  (u16, NETWORK byte order -- ntohs!)
 *     inp_vflag@80 (bit0 v4, bit1 v6)
 *     inp_dependfaddr@84 / inp_dependladdr@100 (16-byte v6 unions;
 *     IPv4 travels v4-mapped, so the v4 bytes are @96 / @112)
 *   inside struct otcpcb (204B @212): t_segq@0 t_dupacks@4 unused@8
 *     t_timer[4]@12 t_inpcb@28 t_state@32  -> TCP state @ entry+244
 *   inside struct xsocket (100B): xso_protocol@+20 xso_family@+24,
 *     so_rcv.sb_cc@+48, so_snd.sb_cc@+72
 *
 * Static asserts pin the sizes; a mismatch with a future kernel fails
 * the build instead of printing garbage.
 *
 * output format follows BSD/Darwin netstat (columns, dot-separated
 * address.port, tcp4/tcp6 labels, "default" route, * for wildcard).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/route.h>
#include <net/if_dl.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <netinet/tcp_fsm.h>
#include <arpa/inet.h>

/* ------------------------------------------------------------------ */
/* kernel ABI, device-measured (see header comment)                    */
/* ------------------------------------------------------------------ */

#pragma pack(4)

struct xig {                    /* xinpgen: chain header/trailer, 24B */
    unsigned int   xig_len;
    unsigned int   xig_count;
    unsigned long long xig_gen;
    unsigned long long xig_sogen;
};

struct xsb {                    /* xsockbuf: 24B */
    unsigned int   sb_cc;
    unsigned int   sb_hiwat;
    unsigned int   sb_mbcnt;
    unsigned int   sb_mbmax;
    int            sb_lowat;
    short          sb_flags;
    short          sb_timeo;
};

struct xso {                    /* xsocket: 100B (armv7, 4-byte ptr) */
    unsigned int   xso_len;
    void          *xso_so;
    short          so_type;
    short          so_options;
    short          so_linger;
    short          so_state;
    void          *so_pcb;
    int            xso_protocol;
    int            xso_family;
    short          so_qlen;
    short          so_incqlen;
    short          so_qlimit;
    short          so_timeo;
    unsigned short so_error;
    int            so_pgid;     /* pid_t */
    unsigned int   so_oobmark;
    struct xsb     so_rcv;
    struct xsb     so_snd;
    unsigned int   so_uid;      /* uid_t */
};

struct inpcb_compat {           /* userland inpcb form: 208B */
    void          *le_next, *le_prev;          /* inp_hash   */
    unsigned int   reserved1, reserved2;
    unsigned short inp_fport;                  /* network order */
    unsigned short inp_lport;                  /* network order */
    void          *il_next, *il_prev;          /* inp_list   */
    void          *inp_ppcb;
    void          *inp_pcbinfo;
    void          *inp_socket;
    unsigned char  nat_owner;
    unsigned char  __pad0[3];
    unsigned int   nat_cookie;
    void          *pl_next, *pl_prev;          /* inp_portlist */
    void          *inp_phd;
    unsigned long long inp_gencnt;             /* pack(4): @60 */
    unsigned int   inp_flags;
    unsigned int   inp_flow;
    unsigned char  inp_vflag;
    unsigned char  inp_ip_ttl;
    unsigned char  inp_ip_p;
    unsigned char  __pad1;
    unsigned char  dependfaddr[16];            /* in6 union, v4-mapped */
    unsigned char  dependladdr[16];
    unsigned char  dependroute[32];
    unsigned char  depend4[12];
    unsigned char  depend6[28];
    int            hash_element;
    void          *inp_saved_ppcb;
    void          *inp_sp;
    unsigned int   reserved3[3];
};

struct otcpcb {                 /* Jaguar-compat tcpcb export: 204B */
    unsigned int   t_segq;
    int            t_dupacks;
    unsigned int   unused;
    int            t_timer[4];  /* TCPT_NTIMERS_EXT = 4 */
    void          *t_inpcb;
    int            t_state;     /* TCPS_* from netinet/tcp_fsm.h */
    unsigned int   t_flags;
    unsigned char  t_tail[204 - 40];            /* not consumed */
};

struct xinpcb_e {               /* udp/raw sysctl entry: 320B */
    unsigned int          xi_len;
    struct inpcb_compat   inp;
    struct xso            so;
    unsigned long long    alignhack;
};

struct xtcpcb_e {               /* tcp sysctl entry: 524B */
    unsigned int          xt_len;
    struct inpcb_compat   inp;
    struct otcpcb         tp;
    struct xso            so;
    unsigned long long    alignhack;
};

#pragma pack()

/* layout is part of the port's contract: fail the build, not the output */
typedef char _assert_xig[(sizeof(struct xig) == 24) - 1];
typedef char _assert_xso[(sizeof(struct xso) == 100) - 1];
typedef char _assert_inpcb[(sizeof(struct inpcb_compat) == 208) - 1];
typedef char _assert_otcpcb[(sizeof(struct otcpcb) == 204) - 1];
typedef char _assert_xinpcb[(sizeof(struct xinpcb_e) == 320) - 1];
typedef char _assert_xtcpcb[(sizeof(struct xtcpcb_e) == 524) - 1];
typedef char _assert_tstate[(offsetof(struct xtcpcb_e, tp.t_state) == 244) - 1];

/* ------------------------------------------------------------------ */
/* helpers                                                             */
/* ------------------------------------------------------------------ */

static const char *st_name(int s)
{
    if (s < 0) return "?";
    if (s < TCPS_LISTEN) return "CLOSED";
    switch (s) {
    case TCPS_LISTEN:     return "LISTEN";
    case TCPS_SYN_SENT:   return "SYN_SENT";
    case TCPS_SYN_RECEIVED: return "SYN_RCVD";
    case TCPS_ESTABLISHED: return "ESTABLISHED";
    case TCPS_CLOSE_WAIT: return "CLOSE_WAIT";
    case TCPS_FIN_WAIT_1: return "FIN_WAIT_1";
    case TCPS_CLOSING:    return "CLOSING";
    case TCPS_LAST_ACK:   return "LAST_ACK";
    case TCPS_FIN_WAIT_2: return "FIN_WAIT_2";
    case TCPS_TIME_WAIT:  return "TIME_WAIT";
    default:              return "?";
    }
}

/* this kernel stores IPv4 addresses in the inp6 union as the v4-COMPATIBLE
 * form ::a.b.c.d (12 zero bytes + v4), not the ::ffff:a.b.c.d mapped form
 * -- measured on device 2026-11-13.  Both render as a dotted quad. */
static int is_v4in6(const unsigned char *p)
{
    static const unsigned char z[12] = {0};
    return memcmp(p, z, 12) == 0;
}

/* format a 16-byte v6 union member: v4 form -> dotted quad, else v6 */
static void fmt_addr(const unsigned char *p, char *out, size_t n)
{
    if (is_v4in6(p))
        snprintf(out, n, "%u.%u.%u.%u", p[12], p[13], p[14], p[15]);
    else
        inet_ntop(AF_INET6, p, out, n);
}

/* dotted netstat style: <addr>.<port>, * for wildcard */
static void fmt_ep(const unsigned char *a, unsigned port, int wild, char *out, size_t n)
{
    char ab[64];
    if (wild) {
        if (port) snprintf(out, n, "*.%u", port);
        else      snprintf(out, n, "*.*");
        return;
    }
    fmt_addr(a, ab, sizeof ab);
    snprintf(out, n, "%s.%u", ab, port);
}

static int addr_wild(const unsigned char *a)
{
    static const unsigned char z[16] = {0};
    return memcmp(a, z, 16) == 0;
}

static unsigned char *fetch_mib(const char *mib, size_t *outlen)
{
    size_t len = 0;
    if (sysctlbyname(mib, NULL, &len, NULL, 0) != 0 || len == 0)
        return NULL;
    unsigned char *buf = malloc(len);
    if (!buf) return NULL;
    if (sysctlbyname(mib, buf, &len, NULL, 0) != 0) { free(buf); return NULL; }
    *outlen = len;
    return buf;
}

/* ------------------------------------------------------------------ */
/* sockets (-t -u -a)                                                  */
/* ------------------------------------------------------------------ */

struct if_ent { int index; char name[IFNAMSIZ]; };

static struct if_ent g_ifmap[64];
static int g_nifmap;

static const char *ifname(int idx)
{
    int i;
    for (i = 0; i < g_nifmap; i++)
        if (g_ifmap[i].index == idx) return g_ifmap[i].name;
    return "?";
}

static unsigned char *rtm_end(unsigned char *msg, int msglen) { return msg + msglen; }

/* index->name map.  Primary source is getifaddrs (works unprivileged);
 * NET_RT_IFLIST is only a fallback because the kernel hides the lladdr
 * sockaddr (RTMF_HIDE_LLADDR) from non-root callers, which removes the
 * name we would harvest from the RTM_IFINFO message. */
static void build_ifmap(void)
{
    struct ifaddrs *ifa = NULL, *it;

    if (getifaddrs(&ifa) == 0 && ifa) {
        for (it = ifa; it; it = it->ifa_next) {
            struct sockaddr_dl *dl;
            int i, nl;
            if (!it->ifa_addr || it->ifa_addr->sa_family != AF_LINK ||
                !it->ifa_name)
                continue;
            dl = (struct sockaddr_dl *)it->ifa_addr;
            if (dl->sdl_index == 0) continue;
            for (i = 0; i < g_nifmap; i++)
                if (g_ifmap[i].index == (int)dl->sdl_index) break;
            if (i < g_nifmap) continue;
            if (g_nifmap >= 64) break;
            nl = strlen(it->ifa_name);
            if (nl >= IFNAMSIZ) nl = IFNAMSIZ - 1;
            memcpy(g_ifmap[g_nifmap].name, it->ifa_name, nl);
            g_ifmap[g_nifmap].name[nl] = 0;
            g_ifmap[g_nifmap].index = dl->sdl_index;
            g_nifmap++;
        }
        freeifaddrs(ifa);
        if (g_nifmap > 0) return;
    }

    /* fallback: NET_RT_IFLIST; names live in the RTM_IFINFO(2) message's
     * RTAX_IFP sockaddr_dl (RTM_NEWADDR carries just IFA/NETMASK/BRD) */
    {
        int mib[6] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST, 0 };
        size_t len = 0;
        unsigned char *buf, *p, *end;
        if (sysctl(mib, 6, NULL, &len, NULL, 0) != 0 || len == 0) return;
        buf = malloc(len);
        if (!buf) return;
        if (sysctl(mib, 6, buf, &len, NULL, 0) != 0) { free(buf); return; }
        p = buf; end = buf + len;
        while (p + 8 <= end) {
            struct if_msghdr *im = (struct if_msghdr *)p;
            int is2, hdrsz, bit, addrs;
            unsigned char *sa;
            if (im->ifm_msglen < 8 || p + im->ifm_msglen > end)
                break;
            is2 = (im->ifm_type == RTM_IFINFO2);
            if (im->ifm_type != RTM_IFINFO && !is2) { p += im->ifm_msglen; continue; }
            hdrsz = is2 ? (int)sizeof(struct if_msghdr2) : (int)sizeof(struct if_msghdr);
            if (im->ifm_msglen < hdrsz) { p += im->ifm_msglen; continue; }
            addrs = im->ifm_addrs;
            sa = p + hdrsz;
            for (bit = 0; bit < RTAX_MAX && sa < (unsigned char *)rtm_end(p, im->ifm_msglen); bit++) {
                struct sockaddr *s = (struct sockaddr *)sa;
                int advance;
                if (!(addrs & (1 << bit))) continue;
                if (bit == RTAX_IFP) {
                    if (s->sa_family == AF_LINK) {
                        struct sockaddr_dl *dl = (struct sockaddr_dl *)s;
                        int i, nl = dl->sdl_nlen;
                        if (nl >= IFNAMSIZ) nl = IFNAMSIZ - 1;
                        for (i = 0; i < g_nifmap; i++)
                            if (g_ifmap[i].index == im->ifm_index) break;
                        if (i == g_nifmap && g_nifmap < 64) {
                            memcpy(g_ifmap[i].name, dl->sdl_data, nl);
                            g_ifmap[i].name[nl] = 0;
                            g_ifmap[i].index = im->ifm_index;
                            g_nifmap++;
                        }
                    }
                    break;
                }
                advance = s->sa_len ? ((s->sa_len + 3) & ~3) : 4;
                sa += advance;
                if (sa > (unsigned char *)rtm_end(p, im->ifm_msglen)) break;
            }
            p += im->ifm_msglen;
        }
        free(buf);
    }
}

static void sockets(int want_tcp, int want_udp, int aflag)
{
    static const struct { const char *mib; size_t ent; int is_tcp; } t[] = {
        { "net.inet.tcp.pcblist", sizeof(struct xtcpcb_e), 1 },
        { "net.inet.udp.pcblist", sizeof(struct xinpcb_e), 0 },
    };
    int ti, shown_header = 0;

    for (ti = 0; ti < 2; ti++) {
        size_t len;
        unsigned char *buf, *p, *end;
        struct xig *h;
        int n = 0;
        int is_tcp = t[ti].is_tcp;
        int shown = is_tcp ? (want_tcp || (aflag && !want_udp))
                           : (want_udp || (aflag && !want_tcp));

        if (!shown) continue;

        buf = fetch_mib(t[ti].mib, &len);
        if (!buf) continue;
        h = (struct xig *)buf;
        if (len < 2 * sizeof(struct xig) || h->xig_len != sizeof(struct xig)) {
            free(buf);
            continue;
        }
        if (!shown_header) {
            printf("Active Internet connections");
            if (aflag) printf(" (including servers)");
            printf("\n%-6s %-7s %-7s %-22s %-22s %s\n",
                   "Proto", "Recv-Q", "Send-Q", "Local Address",
                   "Foreign Address", "(state)");
            shown_header = 1;
        }

        p = buf + sizeof(struct xig);
        end = buf + len - sizeof(struct xig);
        while (p + t[ti].ent <= end) {
            struct inpcb_compat *inp;
            struct xso *so;
            unsigned char *laddr, *faddr;
            unsigned lport, fport;
            char lb[80], fb[80];
            int wild_l, wild_f;

            if (*(unsigned int *)p != t[ti].ent) {  /* corrupted stride */
                printf("%-6s bad entry len %u, aborting walk\n",
                       is_tcp ? "tcp?" : "udp?", *(unsigned int *)p);
                break;
            }
            inp = (struct inpcb_compat *)(p + 4);
            so  = (struct xso *)(p + (is_tcp ? 416 : 212));
            laddr = inp->dependladdr;
            faddr = inp->dependfaddr;
            lport = ntohs(inp->inp_lport);   /* network byte order! */
            fport = ntohs(inp->inp_fport);

            /* netstat semantics: local "*.<port>" when the local address
             * is the wildcard; foreign "*.*" when unconnected (fport 0) */
            wild_l = addr_wild(laddr);
            wild_f = (fport == 0);

            fmt_ep(laddr, lport, wild_l, lb, sizeof lb);
            fmt_ep(faddr, fport, wild_f, fb, sizeof fb);

            if (is_tcp) {
                struct otcpcb *tp = (struct otcpcb *)(p + 212);
                int st = tp->t_state;
                if (!aflag && st == TCPS_LISTEN) { p += t[ti].ent; n++; continue; }
                printf("%-6s %-7u %-7u %-22s %-22s %s\n",
                       (inp->inp_vflag & 1) ? "tcp4" : "tcp6",
                       so->so_rcv.sb_cc, so->so_snd.sb_cc, lb, fb,
                       st_name(st));
            } else {
                printf("%-6s %-7u %-7u %-22s %-22s\n",
                       (so->xso_family == AF_INET) ? "udp4" : "udp6",
                       so->so_rcv.sb_cc, so->so_snd.sb_cc, lb, fb);
            }
            p += t[ti].ent;
            n++;
        }
        free(buf);
    }
}

/* ------------------------------------------------------------------ */
/* routes (-r)                                                         */
/* ------------------------------------------------------------------ */

static void fmt_sockaddr(struct sockaddr *sa, char *out, size_t n)
{
    if (!sa || sa->sa_len == 0) { snprintf(out, n, "--"); return; }
    switch (sa->sa_family) {
    case AF_INET: {
        struct sockaddr_in *sin = (struct sockaddr_in *)sa;
        snprintf(out, n, "%s", inet_ntoa(sin->sin_addr));
        break;
    }
    case AF_INET6: {
        struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)sa;
        char ab[64];
        inet_ntop(AF_INET6, &sin6->sin6_addr, ab, sizeof ab);
        snprintf(out, n, "%s", ab);
        break;
    }
    case AF_LINK: {
        struct sockaddr_dl *dl = (struct sockaddr_dl *)sa;
        snprintf(out, n, "link#%u", dl->sdl_index);
        break;
    }
    default:
        snprintf(out, n, "af%d", sa->sa_family);
    }
}

static int mask_prefixlen(struct sockaddr *sa)
{
    unsigned char *p;
    int i, len = 0;
    if (!sa || sa->sa_len == 0) return 0;
    if (sa->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)sa;
        p = (unsigned char *)&sin->sin_addr;
        for (i = 0; i < 4; i++) {
            unsigned b = p[i];
            while (b & 0x80) { len++; b <<= 1; }
            if (b) return -1;   /* non-contiguous */
        }
        return len;
    }
    if (sa->sa_family == AF_INET6) {
        struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)sa;
        p = (unsigned char *)&sin6->sin6_addr;
        for (i = 0; i < 16; i++) {
            unsigned b = p[i];
            while (b & 0x80) { len++; b <<= 1; }
            if (b) return -1;
        }
        return len;
    }
    return 0;
}

static const char *rflags(int f)
{
    static char s[16];
    char *o = s;
    if (f & RTF_UP)        *o++ = 'U';
    if (f & RTF_GATEWAY)   *o++ = 'G';
    if (f & RTF_HOST)      *o++ = 'H';
    if (f & RTF_STATIC)    *o++ = 'S';
    if (f & RTF_CLONING)   *o++ = 'c';
    if (f & RTF_PRCLONING) *o++ = 'C';
    if (f & RTF_PROTO3)    *o++ = '3';
    if (f & RTF_PROTO2)    *o++ = '2';
    if (f & RTF_PROTO1)    *o++ = '1';
    if (f & RTF_BLACKHOLE) *o++ = 'B';
    if (f & RTF_REJECT)    *o++ = 'R';
    if (f & RTF_DYNAMIC)   *o++ = 'D';
    if (f & RTF_MODIFIED)  *o++ = 'M';
    if (f & RTF_WASCLONED) *o++ = 'W';
    if (f & RTF_LLINFO)    *o++ = 'L';
    if (f & RTF_IFSCOPE)   *o++ = 'I';
    *o = 0;
    return s;
}

static void routes(void)
{
    int mib[6] = { CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0 };
    size_t len = 0;
    unsigned char *buf, *p, *end;
    u_int32_t t_now = (u_int32_t)time(NULL);
    if (sysctl(mib, 6, NULL, &len, NULL, 0) != 0 || len == 0) {
        printf("Routing tables\n\n(no IPv4 route dump available)\n");
        return;
    }
    buf = malloc(len);
    if (!buf) return;
    if (sysctl(mib, 6, buf, &len, NULL, 0) != 0) { free(buf); return; }

    printf("Routing tables\n\n");
    printf("Internet:\n");
    printf("%-19s %-19s %-8s %-6s %-10s %s\n",
           "Destination", "Gateway", "Flags", "Use", "Netif", "Expire");

    p = buf; end = buf + len;
    while (p + sizeof(struct rt_msghdr) <= end) {
        struct rt_msghdr *rtm = (struct rt_msghdr *)p;
        struct sockaddr *sa[RTAX_MAX] = {0};
        unsigned char *sa_p;
        int bit, addrs;
        char dst[64], gw[64];
        char dstf[80];

        if (rtm->rtm_msglen < (u_short)sizeof(struct rt_msghdr) ||
            p + rtm->rtm_msglen > end)
            break;
        if (rtm->rtm_type == RTM_GET) {
            addrs = rtm->rtm_addrs;
            sa_p = p + sizeof(struct rt_msghdr);
            for (bit = 0; bit < RTAX_MAX; bit++) {
                if (addrs & (1 << bit)) {
                    struct sockaddr *s = (struct sockaddr *)sa_p;
                    sa[bit] = s;
                    sa_p += s->sa_len ? ((s->sa_len + 3) & ~3) : 4;
                    if ((unsigned char *)sa_p > p + rtm->rtm_msglen) break;
                }
            }
            fmt_sockaddr(sa[RTAX_DST], dst, sizeof dst);
            fmt_sockaddr(sa[RTAX_GATEWAY], gw, sizeof gw);
            if (strcmp(dst, "0.0.0.0") == 0 &&
                (!sa[RTAX_NETMASK] || mask_prefixlen(sa[RTAX_NETMASK]) == 0))
                snprintf(dstf, sizeof dstf, "default");
            else if (rtm->rtm_flags & RTF_HOST)
                snprintf(dstf, sizeof dstf, "%s", dst);
            else {
                int pl = mask_prefixlen(sa[RTAX_NETMASK]);
                if (pl > 0) snprintf(dstf, sizeof dstf, "%s/%d", dst, pl);
                else        snprintf(dstf, sizeof dstf, "%s", dst);
            }
            printf("%-19s %-19s %-8s %-6u %-10s %u\n",
                   dstf, gw, rflags(rtm->rtm_flags),
                   rtm->rtm_rmx.rmx_pksent,
                   ifname(rtm->rtm_index),
                   rtm->rtm_rmx.rmx_expire > (u_int32_t)t_now
                       ? (unsigned)(rtm->rtm_rmx.rmx_expire - t_now) : 0u);
        }
        p += rtm->rtm_msglen;
    }
    free(buf);
}

/* ------------------------------------------------------------------ */
/* interfaces (-i)                                                     */
/* ------------------------------------------------------------------ */

static void interfaces(void)
{
    int mib2[6] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0 };
    int mib1[6] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST, 0 };
    size_t len = 0;
    unsigned char *buf, *p, *end;
    int use2 = (sysctl(mib2, 6, NULL, &len, NULL, 0) == 0 && len > 0);
    int mib[6];
    memcpy(mib, use2 ? mib2 : mib1, sizeof mib);

    if (sysctl(mib, 6, NULL, &len, NULL, 0) != 0 || len == 0) {
        printf("Name  Mtu   Network       Address              Ipkts Ierrs  Ibytes    Opkts Oerrs  Obytes  Coll\n");
        printf("(no interface list available)\n");
        return;
    }
    buf = malloc(len);
    if (!buf) return;
    if (sysctl(mib, 6, buf, &len, NULL, 0) != 0) { free(buf); return; }

    printf("%-6s %-5s %-13s %-20s %10s %5s %10s %10s %5s %10s %5s\n",
           "Name", "Mtu", "Network", "Address",
           "Ipkts", "Ierrs", "Ibytes", "Opkts", "Oerrs", "Obytes", "Coll");

    p = buf; end = buf + len;
    while (end - p >= 8) {
        struct if_msghdr *ifm = (struct if_msghdr *)p;

        if (ifm->ifm_msglen < 8 || p + ifm->ifm_msglen > end)
            break;

        unsigned char *next_msg = p + ifm->ifm_msglen;

        if (ifm->ifm_type == RTM_IFINFO || ifm->ifm_type == RTM_IFINFO2) {
            char name[IFNAMSIZ] = "?";
            char hw[32] = "";
            int idx = ifm->ifm_index;
            unsigned char *consumed = next_msg;

            unsigned char *sa_p = p + (use2 ? sizeof(struct if_msghdr2)
                                            : sizeof(struct if_msghdr));
            int bit, addrs = ifm->ifm_addrs;
            snprintf(name, sizeof name, "if#%d", idx);

            /* the IFP sockaddr_dl carries name and hardware address */
            for (bit = 0; bit < RTAX_MAX; bit++) {
                struct sockaddr *s;
                if (!(addrs & (1 << bit))) continue;
                s = (struct sockaddr *)sa_p;
                if (bit == RTAX_IFP && s->sa_family == AF_LINK) {
                    struct sockaddr_dl *dl = (struct sockaddr_dl *)s;
                    int nl = dl->sdl_nlen, i;
                    if (nl >= IFNAMSIZ) nl = IFNAMSIZ - 1;
                    memcpy(name, dl->sdl_data, nl);
                    name[nl] = 0;
                    for (i = 0; i < dl->sdl_alen && i < 8; i++) {
                        snprintf(hw + strlen(hw), sizeof hw - strlen(hw),
                                 "%s%02x", i ? ":" : "",
                                 (unsigned char)dl->sdl_data[nl + i]);
                    }
                    break;
                }
                sa_p += s->sa_len ? ((s->sa_len + 3) & ~3) : 4;
                if (sa_p > (unsigned char *)next_msg) break;
            }

            unsigned long long ip = 0, ie = 0, ib = 0, op = 0, oe = 0, ob = 0, co = 0;
            unsigned mtu = 0;
            if (use2) {
                struct if_msghdr2 *m2 = (struct if_msghdr2 *)p;
                mtu = m2->ifm_data.ifi_mtu;
                ip = m2->ifm_data.ifi_ipackets;
                ie = m2->ifm_data.ifi_ierrors;
                ib = m2->ifm_data.ifi_ibytes;
                op = m2->ifm_data.ifi_opackets;
                oe = m2->ifm_data.ifi_oerrors;
                ob = m2->ifm_data.ifi_obytes;
                co = m2->ifm_data.ifi_collisions;
            } else {
                mtu = ifm->ifm_data.ifi_mtu;
                ip = ifm->ifm_data.ifi_ipackets;
                ie = ifm->ifm_data.ifi_ierrors;
                ib = ifm->ifm_data.ifi_ibytes;
                op = ifm->ifm_data.ifi_opackets;
                oe = ifm->ifm_data.ifi_oerrors;
                ob = ifm->ifm_data.ifi_obytes;
                co = ifm->ifm_data.ifi_collisions;
            }
            printf("%-6s %-5u %-13s %-20s %10llu %5llu %10llu %10llu %5llu %10llu %5llu\n",
                   name, mtu, "<Link>", hw[0] ? hw : "",
                   ip, ie, ib, op, oe, ob, co);

            /* addresses attached to this interface follow as RTM_NEWADDR */
            {
                unsigned char *q = next_msg;
                while (q + sizeof(struct ifa_msghdr) <= end) {
                    struct ifa_msghdr *am = (struct ifa_msghdr *)q;
                    unsigned char *sa_p;
                    int bit, addrs;
                    struct sockaddr *ifa_s = NULL, *mask_s = NULL;

                    if (am->ifam_msglen < (int)sizeof(struct ifa_msghdr) ||
                        q + am->ifam_msglen > end ||
                        am->ifam_type != RTM_NEWADDR ||
                        am->ifam_index != idx)
                        break;
                    addrs = am->ifam_addrs;
                    sa_p = q + sizeof(struct ifa_msghdr);
                    for (bit = 0; bit < RTAX_MAX; bit++) {
                        if (addrs & (1 << bit)) {
                            struct sockaddr *s = (struct sockaddr *)sa_p;
                            if (bit == RTAX_IFA) ifa_s = s;
                            else if (bit == RTAX_NETMASK) mask_s = s;
                            sa_p += s->sa_len ? ((s->sa_len + 3) & ~3) : 4;
                            if ((unsigned char *)sa_p > q + am->ifam_msglen) break;
                        }
                    }
                    if (ifa_s) {
                        char net[40], addr[40];
                        int pl = mask_prefixlen(mask_s);
                        fmt_sockaddr(ifa_s, addr, sizeof addr);
                        if (pl > 0)
                            snprintf(net, sizeof net, "%s/%d",
                                     ifa_s->sa_family == AF_INET6 ? "inet6" : "inet", pl);
                        else
                            snprintf(net, sizeof net, "%s",
                                     ifa_s->sa_family == AF_INET6 ? "inet6" : "inet");
                        printf("%-6s %-5u %-13s %-20s %10s %5s %10s %10s %5s %10s %5s\n",
                               name, mtu, net, addr, "-", "-", "-", "-", "-", "-", "-");
                    }
                    consumed = q + am->ifam_msglen;
                    q += am->ifam_msglen;
                }
                p = consumed;
            }
        } else {
            p = next_msg;
        }
    }
    free(buf);
}

/* ------------------------------------------------------------------ */

static void usage(void)
{
    fprintf(stderr,
        "usage: netstat [-a] [-t] [-u] [-r] [-i] [-n]\n"
        "  -a  include listening sockets and UDP/raw (default: active TCP)\n"
        "  -t  TCP only\n"
        "  -u  UDP only (implies -a for the UDP table)\n"
        "  -r  routing table\n"
        "  -i  interfaces with statistics\n"
        "  -n  accepted for compatibility (output is always numeric)\n");
}

int main(int argc, char **argv)
{
    int aflag = 0, tflag = 0, uflag = 0, rflag = 0, iflag = 0;
    int ch;

    while ((ch = getopt(argc, argv, "aturin")) != -1) {
        switch (ch) {
        case 'a': aflag = 1; break;
        case 't': tflag = 1; break;
        case 'u': uflag = 1; aflag = 1; break;
        case 'r': rflag = 1; break;
        case 'i': iflag = 1; break;
        case 'n': break;
        default:  usage(); return 2;
        }
    }
    if (!(tflag || uflag || rflag || iflag || aflag)) {
        /* bare netstat: active TCP connections, like BSD */
        tflag = 1;
    }

    if (iflag || rflag) build_ifmap();
    if (rflag) routes();
    if (iflag) { if (rflag) printf("\n"); interfaces(); }
    if (tflag || uflag || aflag) {
        if (rflag || iflag) printf("\n");
        sockets(tflag, uflag, aflag);
    }
    return 0;
}
