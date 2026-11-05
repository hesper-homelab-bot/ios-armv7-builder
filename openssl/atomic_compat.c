#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#define ATOMIC_LOCK_COUNT 64
typedef int spin_t;
static spin_t locktab[ATOMIC_LOCK_COUNT];
static spin_t *lock_for(const volatile void *p) { return &locktab[(((uintptr_t)p) >> 3) % ATOMIC_LOCK_COUNT]; }
static void spin_lock(spin_t *l) { while (__sync_lock_test_and_set(l, 1)) while (*l) ; }
static void spin_unlock(spin_t *l) { __sync_lock_release(l); }
bool my_atomic_is_lock_free(size_t size, const volatile void *p) { (void)p; return size <= 8; }
void my_atomic_load(size_t size, const volatile void *src, volatile void *dest, int model) {
    spin_t *l = lock_for(src); (void)model;
    spin_lock(l); memcpy((void *)dest, (const void *)src, size); spin_unlock(l);
}
void my_atomic_store(size_t size, volatile void *dest, const volatile void *src, int model) {
    spin_t *l = lock_for(dest); (void)model;
    spin_lock(l); memcpy((void *)dest, (const void *)src, size); spin_unlock(l);
}
bool my_atomic_compare_exchange(size_t size, volatile void *dst, void *expected,
    const volatile void *desired, int success, int failure) {
    spin_t *l = lock_for(dst); (void)success; (void)failure;
    spin_lock(l);
    if (memcmp((void *)dst, expected, size) == 0) {
        memcpy((void *)dst, (const void *)desired, size); spin_unlock(l); return true;
    }
    memcpy(expected, (void *)dst, size); spin_unlock(l); return false;
}
