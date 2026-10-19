; One Java-style check, `icmp ult %i, %len` form (straight out of the front end).
; The header exit `i < n` dominates the check, so the guard is inclusive:
; the fast loop is safe whenever smax(n, 0) <= len.
; RUN: %opt -passes=rce-version -S %s | FileCheck %s
; RUN: %opt -passes=rce-version -pass-remarks=rce-version -disable-output %s 2>&1 | FileCheck %s --check-prefix=REMARK

; REMARK: versioned loop on 1 range check(s); fast copy is check-free

declare void @fail(i32) noreturn cold

define i64 @sum(ptr %a, i32 %len, i32 %n) {
; CHECK-LABEL: define i64 @sum(
; CHECK:       header.rce.check:
; CHECK:         [[SMAX:%.*]] = call i32 @llvm.smax.i32(i32 %n, i32 0)
; CHECK-NEXT:    [[OK:%.*]] = icmp ule i32 [[SMAX]], %len
; CHECK-NEXT:    br i1 [[OK]], label %header.rce.fast.ph, label %header.rce.fast.ph.rce.slow
;
; The slow clone keeps the check and the trap.
; CHECK:       check.rce.slow:
; CHECK-NEXT:    %inb.rce.slow = icmp ult i32 %i.rce.slow, %len
; CHECK-NEXT:    br i1 %inb.rce.slow, label %body.rce.slow, label %trap
;
; The fast loop branches straight to the body.
; CHECK:       check:
; CHECK-NEXT:    br label %body
;
; Only the slow loop can still reach the trap.
; CHECK:       trap:
; CHECK-NEXT:    call void @fail(i32 %i.rce.slow)
; CHECK-NEXT:    unreachable
;
; Both copies feed the one exit.
; CHECK:       exit:
; CHECK-NEXT:    %s.lcssa = phi i64 [ %s, %header ], [ %s.rce.slow, %header.rce.slow ]
entry:
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]
  %s = phi i64 [ 0, %entry ], [ %s.next, %body ]
  %cond = icmp slt i32 %i, %n
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
