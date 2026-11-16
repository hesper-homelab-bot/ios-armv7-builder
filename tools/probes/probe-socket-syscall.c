/* probe-socket-syscall.c -- is the device's socket/connect usable at all?
 *
 * Used to separate "environment/device problem" from "our build is broken"
 * when a ported program's networking dies.  Expected on a healthy device:
 *
 *     socket()  -> fd=3 errno=0
 *     connect() -> r=0 errno=0      (needs outbound net to the hardcoded IP)
 *     DONE
 *
 * When CPython's socket.socket() was crashing here, this probe still passed
 * -- which correctly ruled out the device and pointed at CPython itself.
 * See tools/probes/README.md
 */
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

int main(void) {
    printf("sizeof(struct sockaddr_in)=%zu\n", sizeof(struct sockaddr_in));
    printf("sizeof(struct addrinfo)=%zu\n", sizeof(struct addrinfo));
    fflush(stdout);

    printf("socket()...\n"); fflush(stdout);
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    printf("  fd=%d errno=%d (%s)\n", fd, errno, strerror(errno)); fflush(stdout);

    if (fd >= 0) {
        printf("connect()...\n"); fflush(stdout);
        struct sockaddr_in sa;
        memset(&sa, 0, sizeof sa);
        sa.sin_family = AF_INET;
        sa.sin_port = htons(80);
        sa.sin_addr.s_addr = inet_addr("151.101.64.223");
        int r = connect(fd, (struct sockaddr *)&sa, sizeof sa);
        printf("  r=%d errno=%d (%s)\n", r, errno, strerror(errno)); fflush(stdout);
        close(fd);
    }
    printf("DONE\n");
    return 0;
}
