# Missed-optimization case studies

Everything here is driven by `scripts/missed.sh`, with output in
`results/missed/`. Measurements were taken on an i5-9300H (Skylake core)
under WSL2 with LLVM 20.1.2. AArch64 results are llvm-mca estimates only.

There are two draft reports below. **Neither has been filed.** Each one says
what to check against LLVM main first.

---

## Draft 1: LoopVectorize interleave count drops when the loop body has trivially dead code

**Reproducer:** [`lv-dead-code-ic.ll`](lv-dead-code-ic.ll), a 3-point stencil
loop.

```
opt -passes=loop-vectorize -pass-remarks=loop-vectorize -disable-output lv-dead-code-ic.ll
```

| dead instruction inserted in the body | IC (default) | IC with `-force-target-num-vector-regs=64` | IC after `instcombine` first |
|---|---|---|---|
| none | 4 | 4 | 4 |
| `%dead = add i64 %i, 7` | **2** | 4 | 4 |
| `%dead = icmp ult i64 %i, %len` | **2** | 4 | 4 |
| `%dead = add i64 %len, 1` | 4 | 4 | 4 |
| `%dead = fmul float %r, 3.0` | 4 | 4 | 4 |

Source: [`results/missed/dead_code_ic.csv`](../results/missed/dead_code_ic.csv).

The emitted vector body contains no trace of the dead instruction, so the
code is correct but the decision changes. Only dead users of the induction
variable trigger it, and more vector registers make it go away. That points
at `LoopVectorizationCostModel::calculateRegisterUsage`, which in LLVM 20
walks the IR loop. The cost side does skip trivially dead instructions
(`collectValuesToIgnore`); the register-usage side apparently counts them.

**Why it matters:**
- **Real-world impact is low.** InstCombine and DCE run before LV in the
  default pipelines.
- **It does bite out-of-tree passes at `VectorizerStart`.** It hit this
  repo's pass: the 3-point stencil went from IC 2 to IC 1 and became 5%
  slower than without the pass. That was fixed in the pass by deleting dead
  conditions (`RecursivelyDeleteTriviallyDeadInstructions` in
  `removeCheckExit`).

**Before filing:** LLVM main computes register usage on the VPlan
(`calculateRegisterUsageForPlan` in `VPlanAnalysis.cpp`). VPlan has no recipe
for the dead instruction, so this is probably fixed already. Re-run the
reproducer with `opt` built from main; file only if IC is still 2.

---

## Draft 2: x86 vectorizes histograms by scalarizing them, then runs slower

**Reproducer:** [`hist.c`](hist.c), `hist_count`, which is `counts[keys[i]]++`.

```
clang -O3 -march=skylake -mllvm -enable-histogram-loop-vectorization -S hist.c -Rpass=loop-vectorize
```

LV reports `vectorized loop (vectorization width: 8, interleaved count: 1)`.
The loop body ([`results/missed/hist_x86-avx512+histflag.s`](../results/missed/hist_x86-avx512+histflag.s))
sign-extends and scales the 8 keys as vectors, then moves them out one lane at
a time:

```asm
vmovq   %xmm1, %r9 ; incl (%r9)
vpextrq $1, %xmm1, %r9 ; incl (%r9)
vextracti128 $1, %ymm1, %xmm1 ; ...
```

Measured against the default scalar loop (`hist_bench.c`, 3 runs each,
[`results/missed/hist_perf.csv`](../results/missed/hist_perf.csv)):

| groups | scalar cycles/row | "vectorized" cycles/row | instructions/row |
|---|---|---|---|
| 257 | 1.95–2.09 | 2.13–2.57 | 2.38 → 3.39 |
| 22,754 | 2.71–2.97 | 2.82–3.05 | 2.39 → 3.39 |

The same flag on AArch64 SVE2 produces a real `HISTCNT` loop. On x86, the
cost model treats the scalarized histogram as profitable, and AVX-512's
`vpconflictd` is never used.

**Before filing:** the flag is off by default, and histogram vectorization
was designed for SVE2, so the expected answer may be "x86 lowering is not
implemented yet". The useful report would be about the **cost model**: it
should return Invalid or a high cost for the histogram recipe when the
target has no native lowering. Check main first.

---

## Not a draft: indexed stores and port 7 (gemm axpy)

`gemm_inner.c` and `axpy_addr.S`, with per-port counters in the top-level
README (finding 6). Clang shares one index register across `b` and `c`, so
the stores use indexed addressing and can't issue on Skylake's port 7. This
is a known class of problem: addressing-mode choice in LoopStrengthReduce
vs. Intel's simple-addressing rule for store AGUs. It needs a search of the
existing tracker before anything new is written.
