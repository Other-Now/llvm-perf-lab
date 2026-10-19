	vmovups	(%rdx), %ymm8
	vbroadcastss	(%rdi,%r15), %ymm9
	vfmadd231ps	%ymm9, %ymm8, %ymm0     # ymm0 = (ymm8 * ymm9) + ymm0
	vbroadcastss	(%r12,%r15), %ymm9
	vfmadd231ps	%ymm9, %ymm8, %ymm1     # ymm1 = (ymm8 * ymm9) + ymm1
	vbroadcastss	(%r13,%r15), %ymm9
	vfmadd231ps	%ymm9, %ymm8, %ymm2     # ymm2 = (ymm8 * ymm9) + ymm2
	vbroadcastss	(%rbp,%r15), %ymm9
	vfmadd231ps	%ymm9, %ymm8, %ymm3     # ymm3 = (ymm8 * ymm9) + ymm3
	vbroadcastss	(%r10,%r15), %ymm9
	vfmadd231ps	%ymm9, %ymm8, %ymm4     # ymm4 = (ymm8 * ymm9) + ymm4
	vbroadcastss	(%r11,%r15), %ymm9
	vfmadd231ps	%ymm9, %ymm8, %ymm5     # ymm5 = (ymm8 * ymm9) + ymm5
	vbroadcastss	(%rbx,%r15), %ymm9
	vfmadd231ps	%ymm9, %ymm8, %ymm6     # ymm6 = (ymm8 * ymm9) + ymm6
	vbroadcastss	(%r14,%r15), %ymm9
	vfmadd231ps	%ymm9, %ymm8, %ymm7     # ymm7 = (ymm8 * ymm9) + ymm7
	addq	$4, %r15
	addq	%rcx, %rdx
	cmpq	%r15, %rsi
	jne	.LBB1_2
