; The same check after IndVarSimplify has widened the IV and rewritten the
; check as an exit-count comparison `icmp eq %iv, %len.wide`. This is the form
; the loop is in when the vectorizer runs (and where the plugin is scheduled).
; Exit counts do not care about the spelling, so the pass still versions it;
; upstream IRCE matches `icmp slt/ult` against an IV and does not.
;
; RUN: %opt -passes=rce-version -S %s | FileCheck %s
; RUN: %irce -S %s | FileCheck %s --check-prefix=IRCE

declare void @fail(i64) noreturn cold

; CHECK-LABEL: define i64 @sum_widened(
; The check (header) runs before the latch exit, so the guard is strict:
; n-1 < len.
; CHECK:         [[LAST:%.*]] = add nsw i64 %n.wide, -1
; CHECK-NEXT:    icmp ult i64 [[LAST]], %len.wide
; CHECK:       latch.rce.slow:
; CHECK:       check:
; CHECK-NOT:     icmp eq i64 %iv, %len.wide
; CHECK:         br label %body
;
; IRCE-LABEL: define i64 @sum_widened(
; IRCE-NOT:   postloop
; IRCE-NOT:   preloop
; IRCE:       ret i64
define i64 @sum_widened(ptr %a, i32 %len, i32 %n) {
entry:
  %len.wide = zext i32 %len to i64
  %n.wide = zext i32 %n to i64
  %empty = icmp eq i64 %n.wide, 0
  br i1 %empty, label %exit, label %check

check:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %latch ]
  %s = phi i64 [ 0, %entry ], [ %s.next, %latch ]
  %hit = icmp eq i64 %iv, %len.wide
  br i1 %hit, label %trap, label %body

body:
  %p = getelementptr inbounds i32, ptr %a, i64 %iv
  %v = load i32, ptr %p
  %ve = sext i32 %v to i64
  %s.next = add i64 %s, %ve
  br label %latch

latch:
  %iv.next = add nuw nsw i64 %iv, 1
  %done = icmp eq i64 %iv.next, %n.wide
  br i1 %done, label %exit, label %check

trap:
  call void @fail(i64 %iv)
  unreachable

exit:
  %r = phi i64 [ 0, %entry ], [ %s.next, %latch ]
  ret i64 %r
}
