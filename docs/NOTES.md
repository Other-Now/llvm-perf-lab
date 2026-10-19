# Study notes: llvm-perf-lab

This is the sheet to learn the project from in 1–2 days. Read the README first
for the results. This file holds the theory behind them, how to read every
assembly listing in the repo, and the questions an interviewer is likely to
ask, each with the answer and the file that backs it.

---

## Day 1 morning: the compiler theory the pass uses

### SSA and phis
Every value is assigned exactly once. Where control flow merges, a `phi`
chooses the value according to which predecessor block was taken. A loop's
induction variable is therefore a phi in the header:

```llvm
header:
  %i = phi i32 [ 0, %entry ], [ %i.next, %body ]   ; 0 on entry, %i.next on the back-edge
```

### Dominance
Block A **dominates** B if every path from the entry to B passes through A.
The pass needs this twice:
1. **Deciding inclusive vs strict guards.** If the normal exit's block
   dominates the check's block, the normal exit is tested first within an
   iteration. Then `NormalEC <= CheckEC` is enough. Otherwise the pass needs
   `<` ([RangeCheckVersioning.cpp](../pass/RangeCheckVersioning.cpp), `C.Inclusive`).
2. **SCEV exit counts.** SCEV computes an exit count only for exiting blocks
   that dominate the latch. That is why a check under an `if` is not handled
   (`negative.ll`, `@conditional_check`).

### Canonical loop form (what `simplifyLoop` + `formLCSSA` guarantee)
- **Preheader:** a single block outside the loop whose only successor is the
  header. The guard is placed here.
- **Single latch:** exactly one back-edge.
- **Dedicated exits:** each exit block's predecessors are all inside the
  loop.
- **LCSSA (loop-closed SSA):** any value defined in the loop and used outside
  it goes through a phi in an exit block. This is what makes cloning safe.
  After cloning, the pass only has to add one incoming value per exit phi for
  the clone's exiting block (step 3 in the pass).

### ScalarEvolution (SCEV)
SCEV is LLVM's closed-form algebra for integer values in loops. `{0,+,1}<nsw>`
means "starts at 0 and adds 1 on every iteration, with no signed wrap" (an
*add recurrence*). The pass asks SCEV one question per exiting block:
`getExitCount(L, BB)`, the number of back-edges taken before this exit fires.

- For `for (i = 0; i < n; ++i)` the header exit count is `smax(n, 0)`.
- For the check `i u< len` the exit count is `len`: the check fails when `i`
  reaches `len`.
- The fast loop is safe iff `smax(n,0) <= len`. That is the exact guard in
  `basic.ll`.

### Why exit counts, not `icmp` patterns
By the time the loop vectorizer runs, IndVarSimplify has widened the IV to
i64 and rewritten `icmp ult %i, %len` into `icmp eq %iv.wide, %len.wide`
(`indvars-form.ll`). A pass that pattern-matches `ult` against an IV, as
upstream IRCE does, no longer recognises the check at that point.
Exit counts don't depend on how the compare is spelled.

### Loop versioning vs IRCE vs loop predication
These are three ways to remove a check from the hot loop.

| technique | what it emits | when the check *would* fail late |
|---|---|---|
| **versioning** (this pass) | `if (guard) fast_loop else original_loop` | the whole entry runs the slow loop |
| **IRCE** (upstream) | pre-loop / main loop / post-loop over split index ranges | main loop is still check-free; post-loop takes the check |
| **loop predication** (upstream; widenable branches/guards, as in JVMs) | one check hoisted to the preheader; on failure **deoptimize** | the JIT recompiles; the interpreter re-executes precisely |

A JVM can use predication because it has deoptimization: on failure it falls
back to the interpreter, which re-executes the iteration and throws the
exception at the precise point. A static C compiler has no interpreter to
fall back to, so it must keep an exact copy of the original loop. That is why
this pass versions instead.

### Precise exceptions
Java requires that the exception for `a[i]` be thrown after all earlier side
effects and before any later ones. The slow loop is an untouched clone, so a
failing run traps at the same iteration, with the same memory already
written. `test/difftest.c` checks exactly this: 200k trials × 6 kernels,
about 64% of runs trap, and output memory and the failing (index, length) are
compared byte for byte. `multi.ll` (`@store_then_check`) checks the IR order.

---

## Day 1 afternoon: reading the assembly

### 1. The checked loop's vector body is identical to the unchecked one (`sum`)
`llvm-objdump -d --disassemble-symbols=chk_k_sum ~/lpl-build/obj/chk.o`

```asm
; preheader: vector trip count = min(n-1, len), the check folded into a clamp
leaq   -0x1(%r8), %r9        ; n-1
cmpq   %rcx, %r9             ; vs len
cmovaeq %rcx, %r9            ; r9 = min(n-1, len)
; vector body, the same 8 instructions in chk_, ver_ and unc_:
vpmovsxdq (%rdi,%rax,4), %ymm4 ; load 4 x i32, sign-extend to 4 x i64
vpaddq %ymm4, %ymm0, %ymm0     ; x4, with 4 accumulators (interleave count 4)
...
; scalar tail: the only place the check survives
cmpq   %r9, %rcx ; je -> bounds_fail
```

**What to say:** LoopVectorize supports multiple exits as long as all of them
are *countable*. It runs the vector body for `min(exit counts)` iterations
and leaves the rest, including the iteration that would trap, to a scalar
epilogue. So on LLVM 20 a countable range check does **not** block
vectorization. It costs one `cmov` per loop entry and forces a scalar tail of
1–16 iterations.

### 2. The JCC erratum (identical code, 2.2× apart)
`jcopy` in the checked and versioned builds is byte-identical apart from its
address. In the unpadded build, the versioned copy's loop ended with:

```asm
2cbc: cmpq %rdi, %rcx    ; 3 bytes
2cbf: jne  0x2ca0        ; 2 bytes, spans the 32-byte boundary at 0x2cc0
```

After the 2019 microcode update (Skylake erratum SKX102), a jump that
crosses or ends on a 32-byte boundary can't be cached in the decoded-uop
cache (DSB). The whole loop then comes through the legacy decoders (MITE):
`idq.mite_uops` was 99.9% of uops, and the loop took 5.1 instead of 2.5
cycles/element. `-mbranches-within-32B-boundaries` pads such jumps; all
reported results use it. Raw numbers: `results/no_jcc_padding/perfstat.csv`
vs `results/perfstat.csv`.

### 3. Port 7 and indexed stores (axpy)
```asm
vfmadd213ps (%rdi,%r8), %ymm1, %ymm2   ; load c[j] fused into the FMA
vmovups %ymm2, (%rdi,%r8)              ; store c[j]: INDEXED address
```
Skylake has three address-generation units: ports 2 and 3 handle any
address, and port 7 handles stores with `[base+disp]` addressing only.
Clang shares one index register between `b` and `c`, so every store uses
indexed addressing and has to go through port 2 or 3. Measured per iteration:
p2 = 6.04, p3 = 6.04, **p7 = 0.03**. That is 12 address uops on two ports,
so 6 cycles/iteration, where llvm-mca predicted 4.08. The hand-written twin
in `missed/axpy_addr.S` uses `base+disp` and moves 3.4 uops/iteration onto
port 7, which cuts the median per-iteration time by about 20%.

### 4. Why the 8×8 micro-kernel stops at about 77% of FMA peak
```asm
vmovups (%rdx), %ymm8            ; B row: 1 load
vbroadcastss (%rdi,%r15), %ymm9  ; A[r][k]: 8 broadcast loads
vfmadd231ps %ymm9, %ymm8, %ymm0  ; 8 FMAs
```
That is 9 loads per 8 FMAs. Two load ports give 4.5 cycles per k, while two
FMA ports need only 4.0. Measured: ports 2/3 at 4.6 uops each per k, and
24.5 FLOP/cycle against a 32 peak. BLAS kernels use tiles such as 6×16:
6 broadcasts + 2 B loads = 8 loads per 12 FMAs, which leaves them FMA-bound.
This is the hardware reason micro-kernels have the shapes they do.

### 5. SVE2 `HISTCNT` vs x86 for a histogram
See `results/missed/hist_sve2+histflag.s`:
```asm
ld1w   { z1.s }, p0/z, [x11]               ; keys
histcnt z2.s, p0/z, z1.s, z1.s             ; per lane: how many earlier lanes have the same key
ld1w   { z3.s }, p0/z, [x0, z1.s, sxtw #2] ; gather counts[keys]
mad    z2.s, p0/m, z0.s, z3.s              ; counts + histcnt (z0 = 1)
st1w   { z2.s }, p0, [x0, z1.s, sxtw #2]   ; scatter: duplicate lanes all write the same correct total
```
On x86 with the same flag, LLVM "vectorizes" and then lowers the histogram by
scalarising it: `vmovq`/`vpextrq` per lane plus a scalar `incl`. That is the
scalar loop with extra shuffles: 42% more instructions and 6–20% more cycles
(`results/missed/hist_perf.csv`). AVX-512's `vpconflictd` could implement
the conflict step; LLVM 20 doesn't use it here.

### 6. C2's version of the same loop (`results/java/asm_sumN.txt`)
```asm
cmp ebp, r9d ; jae -> trap       ; pre-loop: check vs length loaded from [array+0xc]
vmovdqu xmm1, [rbx+rbp*4+0x10]   ; main loop: vectorized, NO check
vpmovsxdq ymm1, xmm1 ; vpaddq ...
cmp edi, 0x1f40 ; cmova ...      ; strip mining: inner strips of 8000 iterations
test dword ptr [r11], eax {poll} ; safepoint poll once per strip, not per iteration
call UncommonTrapBlob ;*iaload   ; a failed check deoptimizes; no slow loop exists
```
The C2 listings show three things:
- **Predication does the work.** `-XX:-RangeCheckElimination` alone produces
  **byte-identical** code in JDK 21, because loop predication has already
  hoisted the checks. Turning off `-XX:-UseLoopPredicate` as well leaves the
  checks in the loop and **removes vectorization entirely** (jcopy: 36 ymm
  ops → 0). That is the reverse of LLVM, where the vectorizer works around
  countable checks.
- **jcopy** vectorizes in Java because `arraylength` is immutable. In C the
  same loop is 11.8× slower than unchecked, because the length might alias
  the stores.
- **stencil stays scalar in C2**, and the cause is not aliasing. A freshly
  allocated destination (`stencilFresh`) is still scalar. Bisecting the loop
  shape: `b[i] = 0.5*a[i]` vectorizes, while `a[i] + a[i+1]` and
  `a[i-1] + a[i]` don't. JDK 21's SuperWord gives up when one statement
  combines two references into the same array at different offsets. LLVM
  vectorizes that loop with unaligned loads plus a shuffle.

---

## Day 2: likely questions, with answers

**Q: What did -XX:-RangeCheckElimination do?**
Nothing measurable: the machine code is identical, because loop predication
had already hoisted the checks into predicates before the loop. Only with
`-XX:-UseLoopPredicate` as well do the checks stay inside the loop, and then
C2 also stops vectorizing. Reading the code first is what showed that the
obvious flag measured nothing.

**Q: Any benchmarking mistakes in the Java part?**
Yes. The first JMH run showed Java's `div` 2.5× faster than C. JMH inlined
`Kernels.div(ia, 7, n)`, and C2 turned division by the constant 7 into a
multiply. With the divisor passed through a field, it became a real `idiv`
and 3.2× slower than that first result (2,900 → 9,285 ns/op). My first
hypothesis for `stencil` (aliasing) was also wrong; the bisect above is what
found the real limiter.

**Q: Walk me through your pass.**
A function pass over innermost loops:
1. Canonicalise the loop (simplify form + LCSSA).
2. Sort the exits: an exit to a block that ends in `unreachable` is a check;
   every other exit is normal.
3. Ask SCEV for each exit's count. The normal count is the umin over the
   countable normal exits; uncountable ones can only shorten the loop, so
   they are safe to ignore.
4. For each check, try to prove `Normal < Check` (or `<=` if the normal exit
   dominates the check) statically. If that works, delete the check outright.
   If SCEV proves the opposite, skip: versioning would only ever run the slow
   loop.
5. Otherwise, expand the comparisons in the preheader, split off a new
   preheader, clone the loop with `cloneLoopWithPreheader`, extend the exit
   phis, and delete the check branches in the original copy, which becomes
   the fast one.
6. Recompute the dominator tree and tell SCEV to forget the loop.

**Q: How do you know it's correct?**
Three layers:
- 7 lit/FileCheck tests on hand-written IR, covering positive, negative and
  remark output.
- A differential test of checked vs versioned machine code: 200k random
  trials per kernel, with negative lengths, empty loops, and out-of-range
  gather indices, compared byte for byte, including the trap point and
  partial writes. 0 mismatches.
- The IR verifier runs on every `opt` output.

Alive2 was not used. It reasons about loops only through bounded unrolling,
so it can't prove a versioning transform correct. The differential test is
the honest substitute, and the README says so.

**Q: Did it make anything faster?**
Very little, and explaining why is the result. LLVM 20's vectorizer already
handles countable checks, so `sum` and `saxpy` were identical before and
after. Real wins: `div` −3% (a scalar loop that loses its compare+branch) and
`stencil` −8% (the fast loop gets the same interleave count as unchecked
code). The large gaps, gather at 1.7× and jcopy at 11.8×, come from checks
that *no* range-check elimination can remove under C semantics: an index
loaded from memory, and a length that might alias the stores.

**Q: Then why does a JVM's LLVM backend (Azul Falcon) need anything special?**
Because the facts that make those checks removable are Java facts:
- An array's length is immutable (`!invariant.load`). See
  `test/java-length.ll`: with the tag, LICM hoists the load and the loop
  versions; without it, nothing happens.
- A length is never negative (a `range` attribute). See `test/static.ll`:
  with it, `i < a.length` is proven statically and nothing is cloned;
  without it, SCEV can't prove `smax(len,0) <= len`.
- A failed check can deoptimize instead of keeping a slow loop.

The frontend has to encode these facts in the IR.

**Q: What was the worst bug?**
My own pass made `stencil` 5% slower. It ran right before the vectorizer and
left the dead compares of the deleted checks in the loop. The vectorizer's
interleave count fell from 2 to 1 (unchecked code gets 4). Deleting the dead
compares restored IC 4. The reduced test (`missed/lv-dead-code-ic.ll`) shows
that one dead user of the induction variable halves IC (4 → 2), and that
`-force-target-num-vector-regs=64` restores it. So the cause is LLVM 20's
register-pressure estimate, which runs on IR that still contains the dead
instruction. LLVM main computes register usage on the VPlan instead
(`calculateRegisterUsageForPlan`), so it is probably fixed upstream already.
I didn't file it.

**Q: How did you catch the benchmark lying?**
`jcopy` was 2.4× faster in the versioned build even though the pass had
reported that it couldn't transform that loop. Diffing the disassembly
showed byte-identical code. `perf stat` showed identical instruction counts
and twice the cycles, and then `idq.dsb_uops` against `idq.mite_uops` showed
99.9% legacy-decoder delivery on the slow copy. I looked up the loop's last
`jne`, saw that it straddled a 32-byte boundary, recognised the JCC erratum,
and rebuilt with padding. After that, the DSB share is at least 98% everywhere.

**Q: llvm-mca said 4.08 cycles and you measured 6.3. Who's wrong?**
llvm-mca. Its Skylake model lets the indexed store use port 7. Per-port
dispatch counters show port 7 unused, and 12 address uops on ports 2/3. The
hand-written `base+disp` twin confirms it: port 7 picks up 3.4
uops/iteration. On AArch64 the 12-cycle axpy estimate is also suspect: it
looks like mca chains the post-increment `stp` writeback behind the store
data. That is not verified, since I have no AArch64 hardware.

**Q: What would you do next?**
1. IRCE-style iteration-space splitting, so a check that fails only in the
   last iterations doesn't push the whole loop onto the slow path.
2. Handle checks that don't dominate the latch by computing the IV's range
   instead of an exit count.
3. Check the LV register-pressure behaviour against trunk; if it still
   reproduces, file it with `missed/lv-dead-code-ic.ll`.
4. Run on AArch64 hardware to measure the SVE2 `HISTCNT` loop and to check
   the mca `stp` hypothesis.

---

## Commands to have at your fingertips
```bash
. scripts/env.sh                                     # LLVM 20 + perf on PATH (WSL)
opt -load-pass-plugin ~/lpl-build/RangeCheckVersioning.so -passes=rce-version -S x.ll
clang -O3 -fpass-plugin=.../RangeCheckVersioning.so -Rpass='rce-version|loop-vectorize' x.c
clang -O3 -Rpass-missed=loop-vectorize -Rpass-analysis=loop-vectorize x.c
llvm-mca -mtriple=x86_64 -mcpu=skylake -bottleneck-analysis loop.s
$PERF stat -e cycles,instructions,idq.dsb_uops,idq.mite_uops,uops_dispatched_port.port_7 ./bin
java -XX:+UnlockDiagnosticVMOptions -XX:CompileCommand=print,Cls::m ...   # needs hsdis
```
