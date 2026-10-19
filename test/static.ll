; `for (i = 0; i < a.length; ++i) a[i]` -- the canonical Java loop.
;
; The normal exit count is smax(len, 0) and the check's is len (unsigned).
; smax(len, 0) <=u len holds for every len, but SCEV cannot prove it unless it
; knows len >= 0. A Java array length always is; tell LLVM with `range` and
; the check is deleted at compile time, no clone. Without it the pass falls
; back to versioning on a guard that is always true.
; RUN: %opt -passes=rce-version -S %s | FileCheck %s
; RUN: %opt -passes=rce-version -pass-remarks=rce-version -disable-output %s 2>&1 | FileCheck %s --check-prefix=REMARK

; REMARK: removed 1 range check(s) proven in bounds at compile time
; REMARK: versioned loop on 1 range check(s)

declare void @fail(i32) noreturn cold

; CHECK-LABEL: define i64 @sum_to_len(
; CHECK-NOT:   rce.slow
; CHECK-NOT:   rce.ok
; CHECK-NOT:   call void @fail
; CHECK:       ret i64
define i64 @sum_to_len(ptr %a, i32 range(i32 0, 2147483647) %len) {
entry:
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]
  %s = phi i64 [ 0, %entry ], [ %s.next, %body ]
  %cond = icmp slt i32 %i, %len
  br i1 %cond, label %check, label %exit

check:
  %inb = icmp ult i32 %i, %len
  br i1 %inb, label %body, label %trap

body:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds i32, ptr %a, i64 %ie
  %v = load i32, ptr %p
  %ve = sext i32 %v to i64
  %s.next = add i64 %s, %ve
  %i.next = add nsw i32 %i, 1
  br label %header

trap:
  call void @fail(i32 %i)
  unreachable

exit:
  ret i64 %s
}

; Same loop, sign of len unknown: versioned on smax(len, 0) <= len.
; CHECK-LABEL: define i64 @sum_to_len_unknown_sign(
; CHECK:         [[S:%.*]] = call i32 @llvm.smax.i32(i32 %len, i32 0)
; CHECK-NEXT:    icmp ule i32 [[S]], %len
; CHECK:       check.rce.slow:
define i64 @sum_to_len_unknown_sign(ptr %a, i32 %len) {
entry:
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]
  %s = phi i64 [ 0, %entry ], [ %s.next, %body ]
  %cond = icmp slt i32 %i, %len
  br i1 %cond, label %check, label %exit

check:
  %inb = icmp ult i32 %i, %len
  br i1 %inb, label %body, label %trap

body:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds i32, ptr %a, i64 %ie
  %v = load i32, ptr %p
  %ve = sext i32 %v to i64
  %s.next = add i64 %s, %ve
  %i.next = add nsw i32 %i, 1
  br label %header

trap:
  call void @fail(i32 %i)
  unreachable

exit:
  ret i64 %s
}

; The check is provably taken (n >= 100 > 10 = len): versioning would only
; ever run the slow copy, so the loop is left alone.
; CHECK-LABEL: define void @always_fails(
; CHECK-NOT:   rce.slow
; CHECK:       call void @fail
define void @always_fails(ptr %a) {
entry:
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]
  %cond = icmp ult i32 %i, 100
  br i1 %cond, label %check, label %exit

check:
  %inb = icmp ult i32 %i, 10
  br i1 %inb, label %body, label %trap

body:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds i32, ptr %a, i64 %ie
  store i32 0, ptr %p
  %i.next = add nuw nsw i32 %i, 1
  br label %header

trap:
  call void @fail(i32 %i)
  unreachable

exit:
  ret void
}
