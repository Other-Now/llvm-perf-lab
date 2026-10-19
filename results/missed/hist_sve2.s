	.file	"hist.c"
	.text
	.globl	hist_count                      // -- Begin function hist_count
	.p2align	2
	.type	hist_count,@function
hist_count:                             // @hist_count
// %bb.0:
	cmp	w2, #1
	b.lt	.LBB0_3
// %bb.1:
	mov	w8, w2
.LBB0_2:                                // =>This Inner Loop Header: Depth=1
	ldrsw	x9, [x1], #4
	subs	x8, x8, #1
	ldr	w10, [x0, x9, lsl #2]
	add	w10, w10, #1
	str	w10, [x0, x9, lsl #2]
	b.ne	.LBB0_2
.LBB0_3:
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
