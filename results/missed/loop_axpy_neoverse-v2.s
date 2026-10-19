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
