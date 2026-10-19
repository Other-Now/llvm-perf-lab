; Java arrays carry their length in memory. Inside a loop that stores int32s,
; the length load may alias the stores, so it stays in the loop and the check
; has no loop-invariant exit count. A JIT knows `arraylength` is immutable and
; tells LLVM with !invariant.load; then LICM hoists it and the check versions.
; This is why a JVM's LLVM backend has to annotate its IR -- the C semantics
; alone are not enough.
;
; RUN: opt -passes='loop-mssa(licm)' -S %s | %opt -passes=rce-version -S | FileCheck %s

declare void @fail(i32) noreturn cold

; CHECK-LABEL: define void @plain_load(
; CHECK-NOT:   rce.slow
define void @plain_load(ptr %arr, i32 %n) {
entry:
  %data = getelementptr inbounds i8, ptr %arr, i64 4
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]
  %cond = icmp slt i32 %i, %n
  br i1 %cond, label %check, label %exit

check:
  %len = load i32, ptr %arr
  %inb = icmp ult i32 %i, %len
  br i1 %inb, label %body, label %trap

body:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds i32, ptr %data, i64 %ie
  store i32 %i, ptr %p
  %i.next = add nsw i32 %i, 1
  br label %header

trap:
  call void @fail(i32 %i)
  unreachable

exit:
  ret void
}

; CHECK-LABEL: define void @invariant_length(
; LICM hoists the load into the preheader (dropping the tag on the way), which
; the pass then turns into the guard block.
; CHECK:       header.rce.check:
; CHECK:         %len = load i32, ptr %arr, align 4
; CHECK:         rce.ok
; CHECK:       check.rce.slow:
define void @invariant_length(ptr align 4 dereferenceable(4) %arr, i32 %n) {
entry:
  %data = getelementptr inbounds i8, ptr %arr, i64 4
  br label %header

header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]
  %cond = icmp slt i32 %i, %n
  br i1 %cond, label %check, label %exit

check:
  %len = load i32, ptr %arr, align 4, !invariant.load !0
  %inb = icmp ult i32 %i, %len
  br i1 %inb, label %body, label %trap

body:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds i32, ptr %data, i64 %ie
  store i32 %i, ptr %p
  %i.next = add nsw i32 %i, 1
  br label %header

trap:
  call void @fail(i32 %i)
  unreachable

exit:
  ret void
}

!0 = !{}
