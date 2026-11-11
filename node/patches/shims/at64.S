@ armv7 64-bit atomic libcalls -- REAL implementations (LDREXD/STREXD + dmb).
@ The iOS 10.3.3 device's out-of-line helpers are broken: ___atomic_load_8 is
@ a NO-OP (proven on device).  clang lowers 64-bit __atomic builtins on armv7
@ to these libcalls, so every 64-bit std::atomic in node/V8/libc++ silently
@ reads garbage.  compiler-rt-compatible set; AAPCS: 64-bit scalar args in
@ EVEN:ODD pairs (f(T* p, T v, int m) = r0=p, r1=SKIP, r2=v_lo, r3=v_hi);
@ 64-bit returns in r0:r1; r12 = only true scratch.

	.text
	.syntax unified
	.thumb

	.globl	___atomic_load_8
	.thumb_func
___atomic_load_8:
	push	{r4, r5, r6, lr}
	dmb	ish
1:	ldrexd	r4, r5, [r0]
	strexd	r6, r4, r5, [r0]
	cmp	r6, #0
	bne	1b
	strd	r4, r5, [r1]
	pop	{r4, r5, r6, pc}

	.globl	___atomic_store_8
	.thumb_func
___atomic_store_8:
	push	{r4, r5, r6, r7, lr}
	ldrd	r4, r5, [r1]
	dmb	ish
1:	ldrexd	r6, r7, [r0]
	strexd	r12, r4, r5, [r0]
	cmp	r12, #0
	bne	1b
	dmb	ish
	pop	{r4, r5, r6, r7, pc}

	.globl	___atomic_exchange_8
	.thumb_func
___atomic_exchange_8:
	push	{r4, r5, r6, r7, lr}
	mov	r6, r2			@ ret_ptr (r2 clobbered by ldrexd below)
	ldrd	r4, r5, [r1]		@ new value
	dmb	ish
1:	ldrexd	r2, r3, [r0]
	strexd	r12, r4, r5, [r0]
	cmp	r12, #0
	bne	1b
	strd	r2, r3, [r6]
	dmb	ish
	pop	{r4, r5, r6, r7, pc}

	.globl	___atomic_compare_exchange_8
	.thumb_func
___atomic_compare_exchange_8:
	push	{r4, r5, r6, r7, lr}
	ldrd	r4, r5, [r2]		@ desired
	ldrd	r6, r7, [r1]		@ expected
	dmb	ish
1:	ldrexd	r2, r3, [r0]
	eors	r12, r2, r6
	bne	2f
	eors	r12, r3, r7
	bne	2f
	strexd	r12, r4, r5, [r0]
	cmp	r12, #0
	bne	1b
	movs	r0, #1
	dmb	ish
	pop	{r4, r5, r6, r7, pc}
2:	strd	r2, r3, [r1]
	movs	r0, #0
	dmb	ish
	pop	{r4, r5, r6, r7, pc}

.macro FETCHOP name, instr, instr2
	.globl \name
	.thumb_func
\name:
	push	{r4, r5, r6, r7, lr}
	mov	r4, r2
	mov	r5, r3
	dmb	ish
1:	ldrexd	r2, r3, [r0]
	\instr	r6, r2, r4
	\instr2	r7, r3, r5
	strexd	r12, r6, r7, [r0]
	cmp	r12, #0
	bne	1b
	mov	r0, r2
	mov	r1, r3
	dmb	ish
	pop	{r4, r5, r6, r7, pc}
.endm

	FETCHOP ___atomic_fetch_add_8, adds, adc
	FETCHOP ___atomic_fetch_sub_8, subs, sbc
	FETCHOP ___atomic_fetch_and_8, and,  and
	FETCHOP ___atomic_fetch_or_8,  orr,  orr
	FETCHOP ___atomic_fetch_xor_8, eor,  eor

	.globl	___atomic_load_n_8
	.thumb_func
___atomic_load_n_8:
	push	{r4, r5, r6, lr}
	dmb	ish
1:	ldrexd	r2, r3, [r0]
	strexd	r6, r2, r3, [r0]
	cmp	r6, #0
	bne	1b
	mov	r0, r2
	mov	r1, r3
	dmb	ish
	pop	{r4, r5, r6, pc}

	.globl	___atomic_store_n_8
	.thumb_func
___atomic_store_n_8:
	push	{r4, r5, r6, r7, lr}
	dmb	ish
1:	ldrexd	r4, r5, [r0]
	strexd	r12, r2, r3, [r0]
	cmp	r12, #0
	bne	1b
	dmb	ish
	pop	{r4, r5, r6, r7, pc}

.macro OPFETCH name, instr, instr2
	.globl \name
	.thumb_func
\name:
	push	{r4, r5, r6, r7, lr}
	mov	r4, r2
	mov	r5, r3
	dmb	ish
1:	ldrexd	r2, r3, [r0]
	\instr	r6, r2, r4
	\instr2	r7, r3, r5
	strexd	r12, r6, r7, [r0]
	cmp	r12, #0
	bne	1b
	mov	r0, r6
	mov	r1, r7
	dmb	ish
	pop	{r4, r5, r6, r7, pc}
.endm

	OPFETCH ___atomic_add_fetch_8, adds, adc
	OPFETCH ___atomic_sub_fetch_8, subs, sbc

	.globl	___atomic_load
	.thumb_func
___atomic_load:
	cmp	r0, #8
	beq	1f
	cmp	r0, #4
	beq	2f
	cmp	r0, #2
	beq	3f
	ldrb	r12, [r1]
	strb	r12, [r2]
	bx	lr
3:	ldrh	r12, [r1]
	strh	r12, [r2]
	bx	lr
2:	ldr	r12, [r1]
	str	r12, [r2]
	bx	lr
1:	mov	r0, r1
	mov	r1, r2
	b	___atomic_load_8

	.globl	___atomic_store
	.thumb_func
___atomic_store:
	cmp	r0, #8
	beq	1f
	cmp	r0, #4
	beq	2f
	cmp	r0, #2
	beq	3f
	ldrb	r12, [r2]
	strb	r12, [r1]
	bx	lr
3:	ldrh	r12, [r2]
	strh	r12, [r1]
	bx	lr
2:	ldr	r12, [r2]
	str	r12, [r1]
	bx	lr
1:	mov	r0, r1
	mov	r1, r2
	b	___atomic_store_8

	.end
