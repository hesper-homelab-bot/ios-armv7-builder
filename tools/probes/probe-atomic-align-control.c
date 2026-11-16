/* probe-atomic-align-control.c -- the safe half of the alignment question.
 *
 * Companion to probe-atomic-align.c (which deliberately triggers SIGBUS).
 * This one proves the two things we rely on for the fix:
 *   1. splitting an int64 into two 32-bit atomic reads is CORRECT here
 *   2. an 8-byte atomic IS fine when the object is really 8-byte aligned
 *
 * So the problem is alignment, not "8-byte atomics are broken".
 * Expected: every line says OK, then DONE.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
int main(void) {
    uint64_t patterns[] = { 0x0000000000000001ULL, 0x123456789abcdef0ULL, 0xffffffffffffffffULL };
    for (int i = 0; i < 3; i++) {
        int64_t v; memcpy(&v, &patterns[i], 8);
        const volatile uint32_t *p32 = (const volatile uint32_t *)&v;
        uint32_t lo = __atomic_load_n(&p32[0], __ATOMIC_RELAXED);
        __sync_synchronize();
        uint32_t hi = __atomic_load_n(&p32[1], __ATOMIC_RELAXED);
        uint64_t split = ((uint64_t)hi << 32) | lo;
        printf("want=0x%016llx split=0x%016llx %s\n",
               (unsigned long long)patterns[i], (unsigned long long)split,
               split == patterns[i] ? "OK" : "BAD");
        fflush(stdout);
    }
    /* also: does an 8-byte-ALIGNED atomic work? */
    static int64_t aligned8 __attribute__((aligned(8)));
    aligned8 = 0x1122334455667788LL;
    printf("aligned8 mod8=%lu\n", (unsigned long)((uintptr_t)&aligned8 % 8));
    fflush(stdout);
    int64_t r = __atomic_load_n(&aligned8, __ATOMIC_RELAXED);
    printf("aligned atomic8 = 0x%016llx %s\n", (unsigned long long)r,
           r == 0x1122334455667788LL ? "OK" : "BAD");
    printf("DONE\n");
    return 0;
}
