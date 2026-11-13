/*
 * netstat-probe.c -- establish, ON THE DEVICE, what a netstat port needs.
 *
 * The sysroot has no <netinet/in_pcb.h> (fetch-darwin-header.sh did not
 * carry it), so the xinpgen chain is described by a MINIMAL local struct:
 * only the header fields every Darwin/FreeBSD source agrees on, and the
 * raw bytes are dumped so the real stride comes from the device, not from
 * a header guess.
 *
 *  1. MIB visibility: net.inet.{tcp,udp,raw}.pcblist sizes
 *  2. Chain walk: first entries' xh_len values and the stride between them
 *  3. Route table: NET_RT_DUMP size
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/socket.h>

/* Minimal chain header: xh_len at offset 0 is the one field both Darwin and
 * FreeBSD define identically (u_int, byte offset of the next entry). */
struct xg_head {
    unsigned int xh_len;
    unsigned int xh_kind;
};

static size_t mib_len(const char *name) {
    size_t len = 0;
    if (sysctlbyname(name, NULL, &len, NULL, 0) != 0) return 0;
    return len;
}

static void hexdump(const unsigned char *p, int n) {
    for (int i = 0; i < n; i++) printf("%02x%s", p[i], (i % 16 == 15) ? "\n  " : " ");
    if (n % 16) printf("\n");
}

int main(void) {
    /* ---- 1. PCB list MIBs ---- */
    const char *mibs[] = {
        "net.inet.tcp.pcblist", "net.inet.udp.pcblist",
        "net.inet.raw.pcblist", NULL
    };
    for (int i = 0; mibs[i]; i++) {
        size_t len = mib_len(mibs[i]);
        printf("%s: %s (%zu bytes)\n", mibs[i],
               len > 0 ? "PASS" : "FAIL", len);
    }

    /* ---- 2. chain walk, raw evidence ---- */
    size_t len = mib_len("net.inet.tcp.pcblist");
    if (len > 0) {
        char *buf = malloc(len);
        size_t len2 = len;
        if (sysctlbyname("net.inet.tcp.pcblist", buf, &len2, NULL, 0) == 0) {
            unsigned char *p = (unsigned char *)buf, *end = p + len2;
            int n = 0;
            printf("-- tcp pcblist walk (buffer %zu bytes) --\n", len2);
            printf("  first 32 bytes:\n  ");
            hexdump(p, 32);
            while (p + sizeof(struct xg_head) <= end && n < 4) {
                struct xg_head *h = (struct xg_head *)p;
                printf("  entry %d @off=%zu: xh_len=%u xh_kind=%u\n",
                       n, (size_t)(p - (unsigned char *)buf),
                       h->xh_len, h->xh_kind);
                if (h->xh_len == 0 || h->xh_len > (unsigned)(end - p)) {
                    printf("  stop: bad xh_len\n");
                    break;
                }
                p += h->xh_len;
                n++;
            }
        }
        free(buf);
    }

    /* ---- 3. route table dump ---- */
    {
        int mib[6] = { CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0 };
        size_t len = 0;
        if (sysctl(mib, 6, NULL, &len, NULL, 0) == 0 && len > 0)
            printf("NET_RT_DUMP(AF_INET): PASS (%zu bytes)\n", len);
        else
            printf("NET_RT_DUMP(AF_INET): FAIL\n");
    }
    return 0;
}
