.text
.syntax unified
.thumb
.globl ___atomic_is_lock_free
.thumb_func ___atomic_is_lock_free
___atomic_is_lock_free:
	@ armv7 has no lock-free 8-byte atomics (no ldrexd/strexd guarantee
	@ via clang's libcall path).  Report only <= 4 bytes as lock-free so
	@ OpenSSL falls back to its own lock-protected store.
	cmp r0, #4
	bhi ret0
	subs r1, r0, #1
	tst r2, r1
	ite eq
	moveq r0, #1
	movne r0, #0
	bx lr
ret0:
	movs r0, #0
	bx lr
