	.file	"gemm_inner.c"
	.text
	.globl	axpy                            # -- Begin function axpy
	.p2align	4
	.type	axpy,@function
axpy:                                   # @axpy
	.cfi_startproc
# %bb.0:
	testl	%edx, %edx
	jle	.LBB0_13
# %bb.1:
	movl	%edx, %eax
	cmpl	$3, %edx
	ja	.LBB0_3
# %bb.2:
	xorl	%ecx, %ecx
	jmp	.LBB0_12
.LBB0_3:
	cmpl	$32, %edx
	jae	.LBB0_5
# %bb.4:
	xorl	%ecx, %ecx
	jmp	.LBB0_9
.LBB0_5:
	movl	%eax, %ecx
	andl	$2147483616, %ecx               # imm = 0x7FFFFFE0
	vbroadcastss	%xmm0, %ymm1
	movl	%eax, %edx
	shrl	$5, %edx
	andl	$67108863, %edx                 # imm = 0x3FFFFFF
	shlq	$7, %rdx
	xorl	%r8d, %r8d
	.p2align	4
.LBB0_6:                                # =>This Inner Loop Header: Depth=1
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
# %bb.7:
	cmpl	%eax, %ecx
	je	.LBB0_13
# %bb.8:
	testb	$28, %al
	je	.LBB0_12
.LBB0_9:
	movq	%rcx, %rdx
	movl	%eax, %ecx
	andl	$2147483644, %ecx               # imm = 0x7FFFFFFC
	vbroadcastss	%xmm0, %xmm1
	.p2align	4
.LBB0_10:                               # =>This Inner Loop Header: Depth=1
	vmovups	(%rsi,%rdx,4), %xmm2
	vfmadd213ps	(%rdi,%rdx,4), %xmm1, %xmm2 # xmm2 = (xmm1 * xmm2) + mem
	vmovups	%xmm2, (%rdi,%rdx,4)
	addq	$4, %rdx
	cmpq	%rdx, %rcx
	jne	.LBB0_10
# %bb.11:
	cmpl	%eax, %ecx
	je	.LBB0_13
	.p2align	4
.LBB0_12:                               # =>This Inner Loop Header: Depth=1
	vmovss	(%rsi,%rcx,4), %xmm1            # xmm1 = mem[0],zero,zero,zero
	vfmadd213ss	(%rdi,%rcx,4), %xmm0, %xmm1 # xmm1 = (xmm0 * xmm1) + mem
	vmovss	%xmm1, (%rdi,%rcx,4)
	incq	%rcx
	cmpq	%rcx, %rax
	jne	.LBB0_12
.LBB0_13:
	vzeroupper
	retq
.Lfunc_end0:
	.size	axpy, .Lfunc_end0-axpy
	.cfi_endproc
                                        # -- End function
	.globl	micro8x8                        # -- Begin function micro8x8
	.p2align	4
	.type	micro8x8,@function
micro8x8:                               # @micro8x8
	.cfi_startproc
# %bb.0:
	pushq	%rbp
	.cfi_def_cfa_offset 16
	pushq	%r15
	.cfi_def_cfa_offset 24
	pushq	%r14
	.cfi_def_cfa_offset 32
	pushq	%r13
	.cfi_def_cfa_offset 40
	pushq	%r12
	.cfi_def_cfa_offset 48
	pushq	%rbx
	.cfi_def_cfa_offset 56
	.cfi_offset %rbx, -56
	.cfi_offset %r12, -48
	.cfi_offset %r13, -40
	.cfi_offset %r14, -32
	.cfi_offset %r15, -24
	.cfi_offset %rbp, -16
                                        # kill: def $esi killed $esi def $rsi
	vmovups	(%r8), %ymm0
	movslq	%r9d, %rax
	vmovups	(%r8,%rax,4), %ymm1
	leal	(%rax,%rax), %r9d
	movslq	%r9d, %r9
	vmovups	(%r8,%r9,4), %ymm2
	leal	(%rax,%rax,2), %r11d
	movslq	%r11d, %r10
	movq	%r10, -8(%rsp)                  # 8-byte Spill
	vmovups	(%r8,%r10,4), %ymm3
	leal	(,%rax,4), %r11d
	movslq	%r11d, %r10
	movq	%r10, -16(%rsp)                 # 8-byte Spill
	vmovups	(%r8,%r10,4), %ymm4
	leal	(%rax,%rax,4), %r11d
	movslq	%r11d, %r10
	movq	%r10, -24(%rsp)                 # 8-byte Spill
	vmovups	(%r8,%r10,4), %ymm5
	leal	(%r9,%r9,2), %r11d
	movslq	%r11d, %r10
	movq	%r10, -32(%rsp)                 # 8-byte Spill
	vmovups	(%r8,%r10,4), %ymm6
	leal	(,%rax,8), %r11d
	subl	%eax, %r11d
	movslq	%r11d, %r10
	movq	%r10, -40(%rsp)                 # 8-byte Spill
	vmovups	(%r8,%r10,4), %ymm7
	cmpl	$0, 56(%rsp)
	jle	.LBB1_3
# %bb.1:
	leal	(%rsi,%rsi), %r11d
	leal	(%rsi,%rsi,2), %ebx
	leal	(,%rsi,4), %ebp
	leal	(%rsi,%rsi,4), %r14d
	leal	(%r11,%r11,2), %r15d
	leal	(,%rsi,8), %r12d
	subl	%esi, %r12d
	movslq	%ecx, %rcx
	movslq	%esi, %r13
	movslq	%r11d, %r11
	movslq	%ebx, %rbx
	movslq	%ebp, %r10
	movslq	%r14d, %r14
	movslq	%r15d, %r15
	movq	%r9, -48(%rsp)                  # 8-byte Spill
	movslq	%r12d, %r9
	movl	56(%rsp), %esi
	leaq	(%rdi,%r13,4), %r12
	leaq	(%rdi,%r11,4), %r13
	leaq	(%rdi,%rbx,4), %rbp
	leaq	(%rdi,%r10,4), %r10
	leaq	(%rdi,%r14,4), %r11
	leaq	(%rdi,%r15,4), %rbx
	leaq	(%rdi,%r9,4), %r14
	movq	-48(%rsp), %r9                  # 8-byte Reload
	shlq	$2, %rcx
	shlq	$2, %rsi
	xorl	%r15d, %r15d
	.p2align	4
.LBB1_2:                                # =>This Inner Loop Header: Depth=1
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
.LBB1_3:
	vmovups	%ymm0, (%r8)
	vmovups	%ymm1, (%r8,%rax,4)
	vmovups	%ymm2, (%r8,%r9,4)
	movq	-8(%rsp), %rax                  # 8-byte Reload
	vmovups	%ymm3, (%r8,%rax,4)
	movq	-16(%rsp), %rax                 # 8-byte Reload
	vmovups	%ymm4, (%r8,%rax,4)
	movq	-24(%rsp), %rax                 # 8-byte Reload
	vmovups	%ymm5, (%r8,%rax,4)
	movq	-32(%rsp), %rax                 # 8-byte Reload
	vmovups	%ymm6, (%r8,%rax,4)
	movq	-40(%rsp), %rax                 # 8-byte Reload
	vmovups	%ymm7, (%r8,%rax,4)
	popq	%rbx
	.cfi_def_cfa_offset 48
	popq	%r12
	.cfi_def_cfa_offset 40
	popq	%r13
	.cfi_def_cfa_offset 32
	popq	%r14
	.cfi_def_cfa_offset 24
	popq	%r15
	.cfi_def_cfa_offset 16
	popq	%rbp
	.cfi_def_cfa_offset 8
	vzeroupper
	retq
.Lfunc_end1:
	.size	micro8x8, .Lfunc_end1-micro8x8
	.cfi_endproc
                                        # -- End function
	.ident	"Ubuntu clang version 20.1.2 (0ubuntu1~24.04.3)"
	.section	".note.GNU-stack","",@progbits
	.addrsig
