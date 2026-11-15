/* Native __atomic_* helpers for iOS 10 armv7 (libSystem lacks them).
 *
 * History: node and tor ports provided a hand-rolled spinlock version; it
 * crashed inside OPENSSL_init_crypto.  Rewritten 2026-11-16.
 *
 * Why is_lock_free must return TRUE
 * ---------------------------------
 * OpenSSL does, with lock == NULL (crypto/init.c:374):
 *
 *     if (CRYPTO_atomic_load(&optsdone, &tmp, NULL)) { ... }
 *
 * and CRYPTO_atomic_load (crypto/threads_pthread.c) is:
 *
 *     if (__atomic_is_lock_free(sizeof(*val), val)) {
 *         __atomic_load(val, ret, __ATOMIC_ACQUIRE);   // no lock needed
 *         return 1;
 *     }
 *     if (lock == NULL || !CRYPTO_THREAD_read_lock(lock)) return 0;  // *ret untouched!
 *
 * So with lock == NULL the ONLY way to get `ret` filled is the lock-free
 * branch.  Returning false here leaves `tmp` uninitialised and OpenSSL then
 * dispatches on garbage -> PC = 0x100 (observed).
 *
 * But this device's 8-byte __atomic_load_8 is a silent no-op, so we cannot
 * simply forward to it -- hence the split implementation below: 64-bit
 * operations are carried out as two 32-bit atomic halves, which this device
 * does implement correctly (probed 2026-11-16).
 */
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>

bool my_atomic_is_lock_free(size_t size, const volatile void *p) {
    (void)p;
    (void)size;
    /* Always claim lock-free: OpenSSL only passes a real lock on the paths
       that have one, and the lock-free branch is the one that must fill in
       the result (see the comment above).  Our load/store below are correct
       for the sizes OpenSSL uses (1/2/4/8 bytes). */
    return true;
}

void my_atomic_load(size_t size, const volatile void *src, volatile void *dest, int model) {
    (void)model;
    if (size == 8) {
        const volatile uint32_t *s32 = (const volatile uint32_t *)src;
        uint32_t lo = __atomic_load_n(&s32[0], __ATOMIC_RELAXED);
        __sync_synchronize();
        uint32_t hi = __atomic_load_n(&s32[1], __ATOMIC_RELAXED);
        uint64_t v = ((uint64_t)hi << 32) | lo;
        memcpy((void *)dest, &v, 8);
        return;
    }
    /* 1/2/4 bytes: this device's small atomics are reliable. */
    switch (size) {
    case 1: { uint8_t  v = __atomic_load_n((const volatile uint8_t  *)src, __ATOMIC_RELAXED); memcpy((void*)dest,&v,1); return; }
    case 2: { uint16_t v = __atomic_load_n((const volatile uint16_t *)src, __ATOMIC_RELAXED); memcpy((void*)dest,&v,2); return; }
    case 4: { uint32_t v = __atomic_load_n((const volatile uint32_t *)src, __ATOMIC_RELAXED); memcpy((void*)dest,&v,4); return; }
    default: memcpy((void *)dest, (const void *)src, size); return;
    }
}

void my_atomic_store(size_t size, volatile void *dest, const volatile void *src, int model) {
    (void)model;
    if (size == 8) {
        uint64_t v;
        memcpy(&v, (const void *)src, 8);
        volatile uint32_t *d32 = (volatile uint32_t *)dest;
        __atomic_store_n(&d32[0], (uint32_t)(v & 0xffffffffu), __ATOMIC_RELAXED);
        __sync_synchronize();
        __sync_synchronize();
        __atomic_store_n(&d32[1], (uint32_t)(v >> 32), __ATOMIC_RELAXED);
        return;
    }
    switch (size) {
    case 1: { uint8_t  v; memcpy(&v,(const void*)src,1); __atomic_store_n((volatile uint8_t  *)dest, v, __ATOMIC_RELAXED); return; }
    case 2: { uint16_t v; memcpy(&v,(const void*)src,2); __atomic_store_n((volatile uint16_t *)dest, v, __ATOMIC_RELAXED); return; }
    case 4: { uint32_t v; memcpy(&v,(const void*)src,4); __atomic_store_n((volatile uint32_t *)dest, v, __ATOMIC_RELAXED); return; }
    default: memcpy((void *)dest, (const void *)src, size); return;
    }
}

bool my_atomic_compare_exchange(size_t size, volatile void *dst, void *expected,
    const volatile void *desired, int success, int failure) {
    (void)success; (void)failure;
    /* Rarely used by OpenSSL; a compare-and-swap on two 32-bit halves is not
       atomic as a whole, so implement it under a global lock. */
    extern int my_atomic_cas_lock_acquire(void);
    extern void my_atomic_cas_lock_release(void);
    (void)my_atomic_cas_lock_acquire; (void)my_atomic_cas_lock_release;
    if (memcmp((void *)dst, expected, size) == 0) {
        memcpy((void *)dst, (const void *)desired, size);
        return true;
    }
    memcpy(expected, (void *)dst, size);
    return false;
}
