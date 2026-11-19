# tools/shims/c8fixed.S -- __atomic_is_lock_free, the honest armv7 answer.
#
# iOS 10 libSystem exports ___atomic_load / ___atomic_store /
# ___atomic_compare_exchange but NOT the ___atomic_is_lock_free predicate
# (tools/check-undefined.sh catches the dangling reference at link time).
# C source cannot define a clang builtin (docs/toolchain.md §3); assembly can.
#
# Semantics (device-verified in the node port, docs/node.md #11):
#   * 8 bytes -> 0 ALWAYS: the device's 64-bit atomic libcall is a silent
#     no-op (returns garbage), so "lock-free 8" corrupts data -- the
#     OpenSSL CSPRNG incident.
#   * 1/2/4 bytes -> 1 only when the pointer is size-aligned (ldrex/strex).
#
# Shared by: node (patches/link-node.sh), nginx (build.sh wall #7), mosh
# (defensive), python3.  Every label needs .thumb_func: ld64 warns
# "ARM function not 4-byte aligned" for a label without the thumb bit, and
# toolchain.md §3 says never to ignore that warning (ret0 lacked it once).
	.text
	.syntax unified
	.thumb
	.globl ___atomic_is_lock_free
	.thumb_func ___atomic_is_lock_free
___atomic_is_lock_free:
	cmp r0, #4
	bhi ret0
	subs r1, r0, #1
	tst r2, r1
	ite eq
	moveq r0, #1
	movne r0, #0
	bx lr
	.thumb_func ret0
ret0:
	movs r0, #0
	bx lr
