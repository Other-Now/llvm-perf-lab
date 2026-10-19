; Several checks, an offset index, a store before the check, and an extra
; data-dependent exit.
; RUN: %opt -passes=rce-version -S %s | FileCheck %s

declare void @fail(i32) noreturn cold

; saxpy-like: checks against two different lengths -> one guard, two terms.
; CHECK-LABEL: define void @two_lengths(
; CHECK:         [[A:%.*]] = icmp ule i32 [[N:%.*]], %xlen
; CHECK:         [[B:%.*]] = icmp ule i32 [[N]], %ylen
; CHECK:         [[AB:%.*]] = and i1 [[A]], [[B]]
; CHECK:         br i1 [[AB]], label %header.rce.fast.ph
define void @two_lengths(ptr %y, i32 %ylen, ptr %x, i32 %xlen, i32 %n) {
entry:
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]
  %cond = icmp slt i32 %i, %n
  br i1 %cond, label %cx, label %exit

cx:
  %okx = icmp ult i32 %i, %xlen
  br i1 %okx, label %cy, label %trap

cy:
  %oky = icmp ult i32 %i, %ylen
  br i1 %oky, label %body, label %trap

body:
  %ie = zext i32 %i to i64
  %px = getelementptr inbounds float, ptr %x, i64 %ie
  %py = getelementptr inbounds float, ptr %y, i64 %ie
  %vx = load float, ptr %px
  %vy = load float, ptr %py
  %r = fadd float %vx, %vy
  store float %r, ptr %py
  %i.next = add nsw i32 %i, 1
  br label %header

trap:
  call void @fail(i32 %i)
  unreachable

exit:
  ret void
}

; a[i+1] with a store *before* the check in the same iteration. The slow copy
; must keep the order store -> check -> trap, so a failing run leaves exactly
; the same memory behind as the original (Java's precise exceptions).
; CHECK-LABEL: define void @store_then_check(
; CHECK:       body.rce.slow:
; CHECK:         store i32 %i.rce.slow, ptr %p.rce.slow
; CHECK-NEXT:    %j.rce.slow = add nsw i32 %i.rce.slow, 1
; CHECK-NEXT:    %inb.rce.slow = icmp ult i32 %j.rce.slow, %len
; CHECK-NEXT:    br i1 %inb.rce.slow, label %latch.rce.slow, label %trap
; CHECK:       body:
; CHECK:         store i32 %i, ptr %p
; CHECK:         br label %latch
define void @store_then_check(ptr %a, ptr %b, i32 %len, i32 %n) {
entry:
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %cond = icmp slt i32 %i, %n
  br i1 %cond, label %body, label %exit

body:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds i32, ptr %b, i64 %ie
  store i32 %i, ptr %p
  %j = add nsw i32 %i, 1
  %inb = icmp ult i32 %j, %len
  br i1 %inb, label %latch, label %trap

latch:
  %je = zext i32 %j to i64
  %pa = getelementptr inbounds i32, ptr %a, i64 %je
  store i32 %j, ptr %pa
  %i.next = add nsw i32 %i, 1
  br label %header

trap:
  call void @fail(i32 %j)
  unreachable

exit:
  ret void
}

; An extra `break` on loaded data has no exit count. It can only make the loop
; shorter, so ignoring it is safe and the loop is still versioned.
; CHECK-LABEL: define i32 @find_first_zero(
; CHECK:         rce.ok
; CHECK:       header.rce.slow:
define i32 @find_first_zero(ptr %a, i32 %len, i32 %n) {
entry:
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]
  %cond = icmp slt i32 %i, %n
  br i1 %cond, label %check, label %exit

check:
  %inb = icmp ult i32 %i, %len
  br i1 %inb, label %body, label %trap

body:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds i32, ptr %a, i64 %ie
  %v = load i32, ptr %p
  %z = icmp eq i32 %v, 0
  %i.next = add nsw i32 %i, 1
  br i1 %z, label %exit, label %header

trap:
  call void @fail(i32 %i)
  unreachable

exit:
  %r = phi i32 [ -1, %header ], [ %i, %body ]
  ret i32 %r
}
