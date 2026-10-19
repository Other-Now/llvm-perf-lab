; Reduced test: trivially dead instructions in a loop body lower the loop
; vectorizer's interleave count.
;
; Found while building pass/RangeCheckVersioning.cpp, which runs at the
; VectorizerStart extension point and originally left the compare of every
; removed check behind, unused. No cleanup pass runs between there and
; LoopVectorize, so LV saw them. The 3-point stencil's interleave count fell
; from 4 to 1 and the loop got 5% slower in cycles.
;
; scripts/missed.sh instantiates DEAD_N = 0..4 copies of the marked line and
; records the interleave count LoopVectorize picks for each. Results:
; missed/README.md.
;
; In the standard -O2/-O3 pipelines InstCombine/DCE run before LV, so this
; only bites passes inserted at VectorizerStart (plugins, out-of-tree
; frontends). Impact is low, but the cost model is visibly counting code that
; codegen will never emit.

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define void @stencil(ptr noalias %b, ptr noalias %a, i64 %n, i64 %len) #0 {
entry:
  %a.m1 = getelementptr i8, ptr %a, i64 -4
  %a0 = load float, ptr %a, align 4
  br label %loop

loop:
  %prev = phi float [ %a0, %entry ], [ %next, %loop ]
  %i = phi i64 [ 1, %entry ], [ %i.next, %loop ]
  %p.m1 = getelementptr float, ptr %a.m1, i64 %i
  %lm1 = load float, ptr %p.m1, align 4
  %mid = fmul float %prev, 5.000000e-01
  %t = call float @llvm.fmuladd.f32(float %lm1, float 2.500000e-01, float %mid)
  %i.next = add nuw nsw i64 %i, 1
  %p.p1 = getelementptr inbounds float, ptr %a, i64 %i.next
  %next = load float, ptr %p.p1, align 4
  %r = call float @llvm.fmuladd.f32(float %next, float 2.500000e-01, float %t)
  %p.b = getelementptr inbounds float, ptr %b, i64 %i
  store float %r, ptr %p.b, align 4
  ; DEAD
  %done = icmp eq i64 %i.next, %n
  br i1 %done, label %exit, label %loop

exit:
  ret void
}

declare float @llvm.fmuladd.f32(float, float, float)

attributes #0 = { "target-cpu"="skylake" }
