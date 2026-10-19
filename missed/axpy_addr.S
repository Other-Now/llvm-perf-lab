# Two hand-written copies of the loop clang emits for axpy at -O3
# -march=skylake (results/missed/loop_axpy_skylake.s), identical except for
# the addressing mode of the loads/stores to c:
#
#   axpy_indexed  (%rdi,%r8)  -- what clang emits: one shared index register
#   axpy_simple   (%rdi)+disp -- separate pointer bumps for b and c
#
# On Skylake the store-address unit on port 7 only takes [base+disp]. Indexed
# stores fall back to ports 2/3 and compete with the 8 loads per iteration:
# 12 address uops / 2 ports = 6 cycles, instead of the 4 the store port allows.
#
# void axpy_xxx(float* c, const float* b, float a, int n), n % 32 == 0, n > 0
        .text
        .globl  axpy_indexed
        .p2align 5
axpy_indexed:
        vbroadcastss %xmm0, %ymm1
        movslq  %edx, %rdx
        shlq    $2, %rdx
        xorl    %r8d, %r8d
        .p2align 5
1:      vmovups (%rsi,%r8), %ymm2
        vmovups 32(%rsi,%r8), %ymm3
        vmovups 64(%rsi,%r8), %ymm4
        vmovups 96(%rsi,%r8), %ymm5
        vfmadd213ps (%rdi,%r8), %ymm1, %ymm2
        vfmadd213ps 32(%rdi,%r8), %ymm1, %ymm3
        vfmadd213ps 64(%rdi,%r8), %ymm1, %ymm4
        vfmadd213ps 96(%rdi,%r8), %ymm1, %ymm5
        vmovups %ymm2, (%rdi,%r8)
        vmovups %ymm3, 32(%rdi,%r8)
        vmovups %ymm4, 64(%rdi,%r8)
        vmovups %ymm5, 96(%rdi,%r8)
        subq    $-128, %r8
        cmpq    %r8, %rdx
        jne     1b
        vzeroupper
        retq

        .globl  axpy_simple
        .p2align 5
axpy_simple:
        vbroadcastss %xmm0, %ymm1
        movslq  %edx, %rdx
        leaq    (%rsi,%rdx,4), %rdx
        .p2align 5
1:      vmovups (%rsi), %ymm2
        vmovups 32(%rsi), %ymm3
        vmovups 64(%rsi), %ymm4
        vmovups 96(%rsi), %ymm5
        vfmadd213ps (%rdi), %ymm1, %ymm2
        vfmadd213ps 32(%rdi), %ymm1, %ymm3
        vfmadd213ps 64(%rdi), %ymm1, %ymm4
        vfmadd213ps 96(%rdi), %ymm1, %ymm5
        vmovups %ymm2, (%rdi)
        vmovups %ymm3, 32(%rdi)
        vmovups %ymm4, 64(%rdi)
        vmovups %ymm5, 96(%rdi)
        subq    $-128, %rsi
        subq    $-128, %rdi
        cmpq    %rdx, %rsi
        jne     1b
        vzeroupper
        retq
        .section .note.GNU-stack,"",@progbits
