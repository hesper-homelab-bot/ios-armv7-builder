/* probe-atomic-align.c -- does an 8-byte atomic work on Apple armv7?
 *
 * EXPECTED RESULT ON THIS DEVICE (iPad4, iOS 10.3.3, armv7):
 *     sizeof(int64_t)=8   _Alignof(int64_t)=4
 *     __atomic_load_n(<4-byte-aligned int64>)  ->  Bus error: 10
 *
 * The SIGBUS is the POINT of this probe -- it is not a broken test.
 * Apple's 32-bit ARM ABI aligns int64_t to 4 bytes, but ARM's ldrexd/strexd
 * (used for 8-byte atomics) require 8-byte alignment, so the CPU raises an
 * alignment fault.  That single fact is the root cause of the python3
 * `socket.socket()` SIGBUS, node wall #11 and the OpenSSL init crash.
 * See docs/toolchain.md §19.
 *
 * Build/run instructions: tools/probes/README.md
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static int64_t g_val __attribute__((aligned(4)));   /* force 4-byte alignment */

int main(void) {
    printf("sizeof(int64_t)=%zu alignof=%zu\n", sizeof(int64_t), _Alignof(int64_t));
    printf("&g_val=%p  (mod 8 = %lu)\n", (void*)&g_val, (unsigned long)((uintptr_t)&g_val % 8));
    fflush(stdout);

    /* write a known pattern non-atomically */
    uint64_t patterns[] = { 0x0000000000000001ULL, 0x0000000100000002ULL,
                            0x123456789abcdef0ULL, 0xffffffffffffffffULL };
    for (int i = 0; i < 4; i++) {
        memcpy(&g_val, &patterns[i], 8);
        int64_t via_atomic = __atomic_load_n(&g_val, __ATOMIC_RELAXED);
        /* split read, the way the patch does it */
        const volatile uint32_t *p32 = (const volatile uint32_t *)&g_val;
        uint32_t lo = __atomic_load_n(&p32[0], __ATOMIC_RELAXED);
        __sync_synchronize();
        uint32_t hi = __atomic_load_n(&p32[1], __ATOMIC_RELAXED);
        uint64_t split = ((uint64_t)hi << 32) | lo;

        printf("want=0x%016llx  atomic8=0x%016llx %s  split=0x%016llx %s\n",
               (unsigned long long)patterns[i],
               (unsigned long long)via_atomic,
               via_atomic == (int64_t)patterns[i] ? "OK " : "BAD",
               (unsigned long long)split,
               split == patterns[i] ? "OK" : "BAD");
        fflush(stdout);
    }
    printf("DONE\n");
    return 0;
}
