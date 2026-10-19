	.file	"gemm_inner.c"
	.text
	.globl	axpy                            // -- Begin function axpy
	.p2align	4
	.type	axpy,@function
axpy:                                   // @axpy
// %bb.0:
                                        // kill: def $s0 killed $s0 def $q0
	cmp	w2, #1
	b.lt	.LBB0_14
// %bb.1:
	mov	w8, w2
	cmp	w2, #3
	b.hi	.LBB0_3
// %bb.2:
	mov	x9, xzr
	b	.LBB0_12
.LBB0_3:
	cmp	w2, #16
	b.hs	.LBB0_5
// %bb.4:
	mov	x9, xzr
	b	.LBB0_9
.LBB0_5:
	and	x9, x8, #0x7ffffff0
	add	x10, x0, #32
	add	x11, x1, #32
	mov	x12, x9
	.p2align	5, , 16
.LBB0_6:                                // =>This Inner Loop Header: Depth=1
	ldp	q1, q2, [x11, #-32]
	ldp	q3, q4, [x11], #64
	subs	x12, x12, #16
	ldp	q5, q6, [x10, #-32]
	fmla	v6.4s, v2.4s, v0.s[0]
	fmla	v5.4s, v1.4s, v0.s[0]
	ldp	q7, q16, [x10]
	fmla	v7.4s, v3.4s, v0.s[0]
	fmla	v16.4s, v4.4s, v0.s[0]
	stp	q5, q6, [x10, #-32]
	stp	q7, q16, [x10], #64
	b.ne	.LBB0_6
// %bb.7:
	cmp	x9, x8
	b.eq	.LBB0_14
// %bb.8:
	tst	x8, #0xc
	b.eq	.LBB0_12
.LBB0_9:
	mov	x12, x9
	and	x9, x8, #0x7ffffffc
	add	x10, x1, x12, lsl #2
	add	x11, x0, x12, lsl #2
	sub	x12, x12, x9
	.p2align	5, , 16
.LBB0_10:                               // =>This Inner Loop Header: Depth=1
	ldr	q1, [x10], #16
	ldr	q2, [x11]
	adds	x12, x12, #4
	fmla	v2.4s, v1.4s, v0.s[0]
	str	q2, [x11], #16
	b.ne	.LBB0_10
// %bb.11:
	cmp	x9, x8
	b.eq	.LBB0_14
.LBB0_12:
	add	x10, x0, x9, lsl #2
	add	x11, x1, x9, lsl #2
	sub	x8, x8, x9
	.p2align	5, , 16
.LBB0_13:                               // =>This Inner Loop Header: Depth=1
	ldr	s1, [x11], #4
	ldr	s2, [x10]
	subs	x8, x8, #1
	fmadd	s1, s0, s1, s2
	str	s1, [x10], #4
	b.ne	.LBB0_13
.LBB0_14:
	ret
.Lfunc_end0:
	.size	axpy, .Lfunc_end0-axpy
                                        // -- End function
	.globl	micro8x8                        // -- Begin function micro8x8
	.p2align	4
	.type	micro8x8,@function
micro8x8:                               // @micro8x8
// %bb.0:
	mov	w18, #12                        // =0xc
	mov	w12, #20                        // =0x14
	mov	w13, #24                        // =0x18
	mov	w14, #28                        // =0x1c
	add	x8, x4, w5, sxtw #2
	add	x9, x4, w5, sxtw #3
	ldp	q1, q0, [x4]
                                        // kill: def $w6 killed $w6 def $x6
                                        // kill: def $w3 killed $w3 def $x3
	ldp	q2, q3, [x8]
	smaddl	x10, w5, w18, x4
	add	x11, x4, w5, sxtw #4
	smaddl	x12, w5, w12, x4
	smaddl	x13, w5, w13, x4
	ldp	q4, q5, [x9]
	ldp	q16, q17, [x11]
	ldp	q6, q7, [x10]
	smaddl	x14, w5, w14, x4
	ldp	q18, q19, [x12]
	ldp	q20, q21, [x13]
	ldp	q22, q23, [x14]
	cmp	w6, #1
	b.lt	.LBB1_4
// %bb.1:
	str	x19, [sp, #-16]!                // 8-byte Folded Spill
	add	w16, w1, w1, lsl #1
	lsl	w19, w1, #3
	add	w5, w1, w1, lsl #2
	add	x17, x0, w1, sxtw #3
	smaddl	x18, w1, w18, x0
	sbfiz	x3, x3, #2, #32
	ubfiz	x6, x6, #2, #32
	mov	x15, xzr
	lsl	w7, w16, #1
	sub	w19, w19, w1
	add	x16, x0, w1, sxtw #2
	add	x1, x0, w1, sxtw #4
	add	x5, x0, w5, sxtw #2
	add	x7, x0, w7, sxtw #2
	add	x19, x0, w19, sxtw #2
	.p2align	5, , 16
.LBB1_2:                                // =>This Inner Loop Header: Depth=1
	ldp	q24, q25, [x2]
	ldr	s26, [x0, x15]
	add	x2, x2, x3
	fmla	v0.4s, v25.4s, v26.s[0]
	fmla	v1.4s, v24.4s, v26.s[0]
	ldr	s26, [x16, x15]
	fmla	v3.4s, v25.4s, v26.s[0]
	fmla	v2.4s, v24.4s, v26.s[0]
	ldr	s26, [x17, x15]
	fmla	v5.4s, v25.4s, v26.s[0]
	fmla	v4.4s, v24.4s, v26.s[0]
	ldr	s26, [x18, x15]
	fmla	v7.4s, v25.4s, v26.s[0]
	fmla	v6.4s, v24.4s, v26.s[0]
	ldr	s26, [x1, x15]
	fmla	v17.4s, v25.4s, v26.s[0]
	fmla	v16.4s, v24.4s, v26.s[0]
	ldr	s26, [x5, x15]
	fmla	v19.4s, v25.4s, v26.s[0]
	fmla	v18.4s, v24.4s, v26.s[0]
	ldr	s26, [x7, x15]
	fmla	v21.4s, v25.4s, v26.s[0]
	fmla	v20.4s, v24.4s, v26.s[0]
	ldr	s26, [x19, x15]
	add	x15, x15, #4
	fmla	v23.4s, v25.4s, v26.s[0]
	fmla	v22.4s, v24.4s, v26.s[0]
	cmp	x6, x15
	b.ne	.LBB1_2
// %bb.3:
	ldr	x19, [sp], #16                  // 8-byte Folded Reload
.LBB1_4:
	stp	q1, q0, [x4]
	stp	q2, q3, [x8]
	stp	q4, q5, [x9]
	stp	q6, q7, [x10]
	stp	q16, q17, [x11]
	stp	q18, q19, [x12]
	stp	q20, q21, [x13]
	stp	q22, q23, [x14]
	ret
.Lfunc_end1:
	.size	micro8x8, .Lfunc_end1-micro8x8
                                        // -- End function
	.ident	"Ubuntu clang version 20.1.2 (0ubuntu1~24.04.3)"
	.section	".note.GNU-stack","",@progbits
	.addrsig
