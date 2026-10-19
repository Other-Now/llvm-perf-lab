; Loops the pass must leave alone, each with the remark that says why.
; RUN: %opt -passes=rce-version -S %s | FileCheck %s
; RUN: %opt -passes=rce-version -pass-remarks-missed=rce-version -disable-output %s 2>&1 | FileCheck %s --check-prefix=REMARK

declare void @fail(i32) noreturn cold
declare i1 @pred(i32)

; a[idx[i]]: the checked value is loaded, not an induction variable, so no
; exit count exists for it.
; REMARK: range check(s) not versioned: exit count not computable
; CHECK-LABEL: define i64 @gather(
; CHECK-NOT:   rce.slow
define i64 @gather(ptr %a, i32 %len, ptr %idx, i32 %n) {
entry:
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]
  %s = phi i64 [ 0, %entry ], [ %s.next, %body ]
  %cond = icmp slt i32 %i, %n
  br i1 %cond, label %check, label %exit

check:
  %ie = zext i32 %i to i64
  %pj = getelementptr inbounds i32, ptr %idx, i64 %ie
  %j = load i32, ptr %pj
  %inb = icmp ult i32 %j, %len
  br i1 %inb, label %body, label %trap

body:
  %je = zext i32 %j to i64
  %p = getelementptr inbounds i32, ptr %a, i64 %je
  %v = load i32, ptr %p
  %ve = sext i32 %v to i64
  %s.next = add i64 %s, %ve
  %i.next = add nsw i32 %i, 1
  br label %header

trap:
  call void @fail(i32 %j)
  unreachable

exit:
  ret i64 %s
}

; The check sits under a condition, so its block does not dominate the latch;
; SCEV does not compute exit counts for such blocks. (IRCE can do this one.)
; REMARK: range check(s) not versioned: exit count not computable
; CHECK-LABEL: define void @conditional_check(
; CHECK-NOT:   rce.slow
define void @conditional_check(ptr %a, i32 %len, i32 %n) {
entry:
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %cond = icmp slt i32 %i, %n
  br i1 %cond, label %maybe, label %exit

maybe:
  %want = call i1 @pred(i32 %i)
  br i1 %want, label %check, label %latch

check:
  %inb = icmp ult i32 %i, %len
  br i1 %inb, label %store, label %trap

store:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds i32, ptr %a, i64 %ie
  store i32 %i, ptr %p
  br label %latch

latch:
  %i.next = add nsw i32 %i, 1
  br label %header

trap:
  call void @fail(i32 %i)
  unreachable

exit:
  ret void
}

; No countable normal exit (a `while` driven by memory): nothing to compare
; the check's exit count against.
; REMARK: range check(s) not versioned: loop trip count not computable
; CHECK-LABEL: define void @uncounted(
; CHECK-NOT:   rce.slow
define void @uncounted(ptr %a, i32 %len) {
entry:
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]
  %go = call i1 @pred(i32 %i)
  br i1 %go, label %check, label %exit

check:
  %inb = icmp ult i32 %i, %len
  br i1 %inb, label %body, label %trap

body:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds i32, ptr %a, i64 %ie
  store i32 %i, ptr %p
  %i.next = add nsw i32 %i, 1
  br label %header

trap:
  call void @fail(i32 %i)
  unreachable

exit:
  ret void
}
