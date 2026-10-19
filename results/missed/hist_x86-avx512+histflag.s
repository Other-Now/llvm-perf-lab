	.file	"hist.c"
	.text
	.globl	hist_count                      # -- Begin function hist_count
	.p2align	4
	.type	hist_count,@function
hist_count:                             # @hist_count
# %bb.0:
	testl	%edx, %edx
	jle	.LBB0_7
# %bb.1:
	movl	%edx, %eax
	cmpl	$8, %edx
	jae	.LBB0_3
# %bb.2:
	xorl	%ecx, %ecx
	jmp	.LBB0_6
.LBB0_3:
	movl	%eax, %ecx
	andl	$2147483640, %ecx               # imm = 0x7FFFFFF8
	movl	%eax, %edx
	shrl	$3, %edx
	andl	$268435455, %edx                # imm = 0xFFFFFFF
	shlq	$5, %rdx
	xorl	%r8d, %r8d
	vpbroadcastq	%rdi, %ymm0
	.p2align	4
.LBB0_4:                                # =>This Inner Loop Header: Depth=1
	vpmovsxdq	(%rsi,%r8), %ymm1
	vpmovsxdq	16(%rsi,%r8), %ymm2
	vpsllq	$2, %ymm1, %ymm1
	vpaddq	%ymm1, %ymm0, %ymm1
	vmovq	%xmm1, %r9
	incl	(%r9)
	vpextrq	$1, %xmm1, %r9
	incl	(%r9)
	vextracti128	$1, %ymm1, %xmm1
	vmovq	%xmm1, %r9
	incl	(%r9)
	vpextrq	$1, %xmm1, %r9
	incl	(%r9)
	vpsllq	$2, %ymm2, %ymm1
	vpaddq	%ymm1, %ymm0, %ymm1
	vmovq	%xmm1, %r9
	incl	(%r9)
	vpextrq	$1, %xmm1, %r9
	incl	(%r9)
	vextracti128	$1, %ymm1, %xmm1
	vmovq	%xmm1, %r9
	incl	(%r9)
	vpextrq	$1, %xmm1, %r9
	incl	(%r9)
	addq	$32, %r8
	cmpq	%r8, %rdx
	jne	.LBB0_4
# %bb.5:
	cmpl	%eax, %ecx
	je	.LBB0_7
	.p2align	4
.LBB0_6:                                # =>This Inner Loop Header: Depth=1
	movslq	(%rsi,%rcx,4), %rdx
	incl	(%rdi,%rdx,4)
	incq	%rcx
	cmpq	%rcx, %rax
	jne	.LBB0_6
.LBB0_7:
	vzeroupper
	retq
.Lfunc_end0:
	.size	hist_count, .Lfunc_end0-hist_count
                                        # -- End function
	.globl	hist_count_sum                  # -- Begin function hist_count_sum
	.p2align	4
	.type	hist_count_sum,@function
hist_count_sum:                         # @hist_count_sum
# %bb.0:
	testl	%r8d, %r8d
	jle	.LBB1_6
# %bb.1:
	movl	%r8d, %r9d
	movl	%r9d, %eax
	andl	$3, %eax
	cmpl	$4, %r8d
	jae	.LBB1_7
# %bb.2:
	xorl	%r8d, %r8d
	jmp	.LBB1_3
.LBB1_7:
	andl	$2147483644, %r9d               # imm = 0x7FFFFFFC
	xorl	%r8d, %r8d
	.p2align	4
.LBB1_8:                                # =>This Inner Loop Header: Depth=1
	movslq	(%rdx,%r8,4), %r10
	incl	(%rdi,%r10,4)
	movq	(%rcx,%r8,8), %r11
	addq	%r11, (%rsi,%r10,8)
	movslq	4(%rdx,%r8,4), %r10
	incl	(%rdi,%r10,4)
	movq	8(%rcx,%r8,8), %r11
	addq	%r11, (%rsi,%r10,8)
	movslq	8(%rdx,%r8,4), %r10
	incl	(%rdi,%r10,4)
	movq	16(%rcx,%r8,8), %r11
	addq	%r11, (%rsi,%r10,8)
	movslq	12(%rdx,%r8,4), %r10
	incl	(%rdi,%r10,4)
	movq	24(%rcx,%r8,8), %r11
	addq	%r11, (%rsi,%r10,8)
	addq	$4, %r8
	cmpq	%r8, %r9
	jne	.LBB1_8
.LBB1_3:
	testq	%rax, %rax
	je	.LBB1_6
# %bb.4:
	leaq	(%rcx,%r8,8), %rcx
	leaq	(%rdx,%r8,4), %rdx
	xorl	%r8d, %r8d
	.p2align	4
.LBB1_5:                                # =>This Inner Loop Header: Depth=1
	movslq	(%rdx,%r8,4), %r9
	incl	(%rdi,%r9,4)
	movq	(%rcx,%r8,8), %r10
	addq	%r10, (%rsi,%r9,8)
	incq	%r8
	cmpq	%r8, %rax
	jne	.LBB1_5
.LBB1_6:
	retq
.Lfunc_end1:
	.size	hist_count_sum, .Lfunc_end1-hist_count_sum
                                        # -- End function
	.ident	"Ubuntu clang version 20.1.2 (0ubuntu1~24.04.3)"
	.section	".note.GNU-stack","",@progbits
	.addrsig
