	.file	"hist.c"
	.text
	.globl	hist_count                      // -- Begin function hist_count
	.p2align	2
	.type	hist_count,@function
hist_count:                             // @hist_count
// %bb.0:
	cmp	w2, #1
	b.lt	.LBB0_8
// %bb.1:
	mov	w8, w2
	cnth	x9
	cmp	x9, x8
	b.ls	.LBB0_3
// %bb.2:
	mov	x9, xzr
	b	.LBB0_6
.LBB0_3:
	rdvl	x9, #1
	mov	w10, #2147483640                // =0x7ffffff8
	mov	z0.s, #1                        // =0x1
	lsr	x9, x9, #4
	ptrue	p0.s
	mov	x11, x1
	mul	x9, x9, x10
	and	x9, x9, x8
	mov	x10, x9
.LBB0_4:                                // =>This Inner Loop Header: Depth=1
	ld1w	{ z1.s }, p0/z, [x11]
	dech	x10
	histcnt	z2.s, p0/z, z1.s, z1.s
	ld1w	{ z3.s }, p0/z, [x0, z1.s, sxtw #2]
	mad	z2.s, p0/m, z0.s, z3.s
	ld1w	{ z3.s }, p0/z, [x11, #1, mul vl]
	addvl	x11, x11, #2
	st1w	{ z2.s }, p0, [x0, z1.s, sxtw #2]
	histcnt	z1.s, p0/z, z3.s, z3.s
	ld1w	{ z2.s }, p0/z, [x0, z3.s, sxtw #2]
	mad	z1.s, p0/m, z0.s, z2.s
	st1w	{ z1.s }, p0, [x0, z3.s, sxtw #2]
	cbnz	x10, .LBB0_4
// %bb.5:
	cmp	x9, x8
	b.eq	.LBB0_8
.LBB0_6:
	add	x10, x1, x9, lsl #2
	sub	x8, x8, x9
.LBB0_7:                                // =>This Inner Loop Header: Depth=1
	ldrsw	x9, [x10], #4
	subs	x8, x8, #1
	ldr	w11, [x0, x9, lsl #2]
	add	w11, w11, #1
	str	w11, [x0, x9, lsl #2]
	b.ne	.LBB0_7
.LBB0_8:
	ret
.Lfunc_end0:
	.size	hist_count, .Lfunc_end0-hist_count
                                        // -- End function
	.globl	hist_count_sum                  // -- Begin function hist_count_sum
	.p2align	2
	.type	hist_count_sum,@function
hist_count_sum:                         // @hist_count_sum
// %bb.0:
	cmp	w4, #1
	b.lt	.LBB1_3
// %bb.1:
	mov	w8, w4
.LBB1_2:                                // =>This Inner Loop Header: Depth=1
	ldrsw	x9, [x2], #4
	subs	x8, x8, #1
	ldr	x11, [x3], #8
	ldr	w10, [x0, x9, lsl #2]
	ldr	x12, [x1, x9, lsl #3]
	add	w10, w10, #1
	str	w10, [x0, x9, lsl #2]
	add	x10, x12, x11
	str	x10, [x1, x9, lsl #3]
	b.ne	.LBB1_2
.LBB1_3:
	ret
.Lfunc_end1:
	.size	hist_count_sum, .Lfunc_end1-hist_count_sum
                                        // -- End function
	.ident	"Ubuntu clang version 20.1.2 (0ubuntu1~24.04.3)"
	.section	".note.GNU-stack","",@progbits
	.addrsig
