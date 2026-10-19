	vmovups	(%rsi,%r8), %ymm2
	vmovups	32(%rsi,%r8), %ymm3
	vmovups	64(%rsi,%r8), %ymm4
	vmovups	96(%rsi,%r8), %ymm5
	vfmadd213ps	(%rdi,%r8), %ymm1, %ymm2 # ymm2 = (ymm1 * ymm2) + mem
	vfmadd213ps	32(%rdi,%r8), %ymm1, %ymm3 # ymm3 = (ymm1 * ymm3) + mem
	vfmadd213ps	64(%rdi,%r8), %ymm1, %ymm4 # ymm4 = (ymm1 * ymm4) + mem
	vfmadd213ps	96(%rdi,%r8), %ymm1, %ymm5 # ymm5 = (ymm1 * ymm5) + mem
	vmovups	%ymm2, (%rdi,%r8)
	vmovups	%ymm3, 32(%rdi,%r8)
	vmovups	%ymm4, 64(%rdi,%r8)
	vmovups	%ymm5, 96(%rdi,%r8)
	subq	$-128, %r8
	cmpq	%r8, %rdx
	jne	.LBB0_6
