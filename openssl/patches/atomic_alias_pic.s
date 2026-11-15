/* Public __atomic_* symbols for iOS 10 (libSystem lacks them).
 *
 * 2026-11-16: previous version used `bl` (branch-with-link) to reach the
 * my_atomic_* implementations.  That clobbers LR, so after my_atomic_* did
 * `bx lr` control returned to the trampoline with a corrupted link register
 * and the argument registers had already been clobbered -- observed as
 * my_atomic_load(size=1, dest=NULL) and an immediate SIGSEGV at 0x100.
 *
 * Use a plain tail branch (`b`): the callee returns straight to the original
 * caller with LR intact, and arguments pass through untouched.
 *
 * Must be PIC (bundle-safe): a relative `b` needs no relocation at all.
 */
.syntax unified
.thumb
.text

.globl ___atomic_is_lock_free
.thumb_func
___atomic_is_lock_free:
	b	_my_atomic_is_lock_free

.globl ___atomic_load
.thumb_func
___atomic_load:
	b	_my_atomic_load

.globl ___atomic_store
.thumb_func
___atomic_store:
	b	_my_atomic_store

.globl ___atomic_compare_exchange
.thumb_func
___atomic_compare_exchange:
	b	_my_atomic_compare_exchange
