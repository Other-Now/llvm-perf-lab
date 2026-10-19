; A rotated loop with the check still in `icmp ult` form: the shape IRCE was
; written for. Both passes remove the check from the hot loop, differently:
;   rce-version: one runtime test, then either the check-free copy or the
;                original -- an all-or-nothing choice per loop entry.
;   irce:        splits the iteration space into pre/main/post loops, so the
;                main loop is check-free even when the check *would* fail in
;                the last few iterations.
;
; RUN: %opt -passes=rce-version -S %s | FileCheck %s
; RUN: %irce -S %s | FileCheck %s --check-prefix=IRCE

declare void @fail(i32) noreturn cold

; CHECK-LABEL: define void @fill(
; CHECK:         rce.ok
; CHECK:       body.rce.slow:
; CHECK-NOT:   postloop
;
; IRCE-LABEL: define void @fill(
; IRCE:       postloop
define void @fill(ptr %a, i32 %len, i32 %n) {
entry:
  %pos = icmp sgt i32 %n, 0
  br i1 %pos, label %body, label %exit

body:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %inb = icmp ult i32 %i, %len
  br i1 %inb, label %latch, label %trap

latch:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds i32, ptr %a, i64 %ie
  store i32 %i, ptr %p
  %i.next = add nsw i32 %i, 1
  %more = icmp slt i32 %i.next, %n
  br i1 %more, label %body, label %exit

trap:
  call void @fail(i32 %i)
  unreachable

exit:
  ret void
}
