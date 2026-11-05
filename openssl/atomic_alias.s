/* Public __atomic_* symbols for iOS 10 (libSystem lacks them).
   Long-branch stubs (ARM mode: ldr pc, [pc, #-4]). */
.text
.globl ___atomic_is_lock_free
___atomic_is_lock_free:
	ldr	pc, [pc, #-4]
	.word	_my_atomic_is_lock_free
.globl ___atomic_load
___atomic_load:
	ldr	pc, [pc, #-4]
	.word	_my_atomic_load
.globl ___atomic_store
___atomic_store:
	ldr	pc, [pc, #-4]
	.word	_my_atomic_store
.globl ___atomic_compare_exchange
___atomic_compare_exchange:
	ldr	pc, [pc, #-4]
	.word	_my_atomic_compare_exchange
