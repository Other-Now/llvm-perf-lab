# llvm-perf-lab

Range-check elimination, studied from both sides of a JVM. The repo has three
parts:
- an out-of-tree **LLVM pass** that removes Java-style bounds checks by loop
  versioning;
- a **missed-optimization study** of my
  [gemm-lab](https://github.com/Other-Now/gemm-lab) and
  [vecagg-lab](https://github.com/Other-Now/vecagg-lab) inner loops in
  x86-64 and AArch64 assembly;
- the same loops through **HotSpot C2**, read with hsdis.

Every claim about speed below comes with the counter that explains it:
`perf stat` cycles, DSB vs legacy-decoder uops, and per-port dispatch. The
one exception is AArch64, which has no hardware here; its numbers are
llvm-mca estimates and labelled as such.

Machine: Intel i5-9300H (Coffee Lake, Skylake core), WSL2, LLVM 20.1.2,
Temurin 21.0.12. All C timings are median core cycles per element over 5
process runs, from a build padded with `-mbranches-within-32B-boundaries`
(finding 3 explains why).

## Findings

**1. The pass works and is semantically exact.**
[`pass/RangeCheckVersioning.cpp`](pass/RangeCheckVersioning.cpp) is about
360 lines (with comments): a new-pass-manager plugin built on ScalarEvolution exit counts,
LCSSA, and `cloneLoopWithPreheader`. It passes:
- **7 lit/FileCheck tests**: positive, negative and remark output;
- a **differential test** of checked vs versioned machine code with
  **0 mismatches** over 200,000 random trials × 6 kernels. About 64% of runs
  trap, and the failing index, partial writes and return value are compared
  byte for byte. This is Java's precise-exception rule, tested directly.

**2. On LLVM 20 it barely matters, and that is the interesting part.**

| kernel (n = 3000) | checked | versioned | unchecked | what limits it |
|---|---|---|---|---|
| sum | 0.273 | 0.270 | 0.277 | nothing: vector body identical in all three |
| saxpy | 0.225 | 0.235 | 0.218 | within run-to-run noise (about ±5%) |
| stencil | 0.363 | **0.334** | 0.324 | versioned gets unchecked's interleave count |
| div (scalar) | 8.12 | **7.87** | 7.85 | removes cmp+jcc from a scalar loop, −3%, in 3 of 3 runs |
| gather `a[idx[i]]` | 2.20 | 2.10 | **1.29** | the check on loaded `idx[i]` has no exit count |
| jcopy (Java layout) | 2.55 | 2.29 | **0.215** | the length lives in memory and may alias the stores |

Cycles per element; source: [`results/perfstat.csv`](results/perfstat.csv).

The loop vectorizer already handles loops with several *countable* exits. In
`sum`, the checked loop's vector body is **instruction-for-instruction
identical** to the unchecked one. The check is folded into a
`min(n-1, len)` trip-count clamp (`cmovae`) and survives only in a scalar
tail of at most 16 iterations ([docs/NOTES.md](docs/NOTES.md) §1). The two
large gaps come from checks that *no* range-check elimination can remove
under C semantics. Java semantics can remove them (finding 7).

**3. The benchmark lied first: Skylake's JCC erratum, 2.2× on identical code.**
My first run showed the pass making `jcopy` 2.4× faster, even though the pass
had reported that it could not transform that loop. The two builds'
disassembly was byte-identical; `perf stat` showed the same instruction
count and 2.2× the cycles. The cause was `idq.mite_uops` at **99.9%**: the
loop's macro-fused `cmp`/`jne` straddled a 32-byte boundary (`0x2cbc`–
`0x2cc0`), which after the SKX102 microcode fix keeps it out of the uop
cache. With padding, every kernel's DSB share is ≥ 98%. Unpadded numbers are
kept in [`results/no_jcc_padding/`](results/no_jcc_padding/).

**4. My pass's worst bug: dead code halved the vectorizer's interleave count.**
The pass runs at `VectorizerStart` and originally left each removed check's
`icmp` behind. With no cleanup before LoopVectorize, `stencil`'s fast loop was
vectorized at **IC 1** (checked code gets 2, unchecked 4) and ran 5% *slower*
than the checked build. Deleting the dead compares fixed it. The reduced test
[`missed/lv-dead-code-ic.ll`](missed/lv-dead-code-ic.ll) shows that:
- **one** dead instruction using the IV takes IC from 4 to 2;
- dead users of invariants or of vector values don't change it;
- `-force-target-num-vector-regs=64` restores IC 4, which points at the
  register-pressure estimate.

LLVM 20 computes that estimate on IR (`calculateRegisterUsage`); main
computes it on VPlan (`calculateRegisterUsageForPlan`), so it is probably
already fixed upstream. **Not filed.**
[`results/missed/dead_code_ic.csv`](results/missed/dead_code_ic.csv)

**5. vecagg's histogram: SVE2 has an instruction for it; x86 "vectorizes" by scalarizing.**
`counts[keys[i]]++` is not vectorized by default on any target in LLVM 20.
With `-mllvm -enable-histogram-loop-vectorization`:
- **AArch64 SVE2** vectorizes it around `HISTCNT`, which counts the earlier
  lanes holding the same key, so duplicate keys still scatter the right
  total.
- **x86** reports "vectorized loop (width 8)", but the backend lowers the
  histogram one lane at a time: `vmovq`/`vpextrq` plus a scalar `incl` per
  key. Measured here, that is **+42% instructions and +20% cycles at 257
  groups** (+6% at 22,754 groups) over the scalar loop. AVX-512's
  `vpconflictd` isn't used.
- vecagg's real loop (COUNT and SUM together) isn't vectorized on any target.

The x86 regression is a cost-model miss, but it sits behind an off-by-default
flag. **Not filed.**
[`results/missed/hist_perf.csv`](results/missed/hist_perf.csv),
[`hist_sve2+histflag.s`](results/missed/hist_sve2+histflag.s)

**6. gemm's inner loops: where llvm-mca is wrong, and why the micro-kernel stops at 77% of peak.**

| loop (Skylake) | llvm-mca cycles/iter | measured cycles/iter | FLOP/cycle measured | bound |
|---|---|---|---|---|
| axpy `c[j] += a*b[j]` (clang's) | 4.08 | 6.3 | 10.5 | address-generation ports 2/3 |
| micro8x8 (register-blocked) | 4.57 | 5.3–5.7 incl. call overhead | 24.5 | load ports 2/3 (9 loads / 8 FMAs) |

Clang addresses `b` and `c` with one shared index register, so every store
uses an **indexed** address. On Skylake, the port-7 store-address unit only
handles `[base+disp]`. Per-port counters: p2 = 6.04, p3 = 6.04,
**p7 = 0.03** uops per iteration. That is 12 address uops on two ports,
hence 6 cycles. llvm-mca's model lets the stores use port 7 and predicts 4.08.

The hand-written twin in [`missed/axpy_addr.S`](missed/axpy_addr.S) changes
only the addressing mode. It moves 3.4 uops/iteration onto port 7, and the
median time per 32-float iteration goes from **7.45 to 5.96 cycles**. That
comparison is 7 interleaved runs each; the absolute times were noisier that
session than in the first table.

The micro-kernel needs 8 broadcasts + 1 B load per 8 FMAs, which takes 4.6
cycles on the two load ports against 4.0 on the two FMA ports. That is why
BLAS kernels use tiles like 6×16.

On AArch64 (Neoverse V2, **llvm-mca only**), axpy's 12-cycle estimate
against a 2.7-cycle resource bound looks like a modelling artifact around
post-increment `stp`. I can't check that without hardware.
[`results/missed/gemm_mca.csv`](results/missed/gemm_mca.csv),
[`gemm_perf.csv`](results/missed/gemm_perf.csv)

**7. HotSpot C2: predication + deoptimization, and checks matter far more there.**
JMH, ns per call at n = 3000, 3 forks × 10 iterations
([`results/java/`](results/java/)):

| kernel | default | `-RangeCheckElimination` | `-RangeCheckElimination -UseLoopPredicate` | `-UseSuperWord` |
|---|---|---|---|---|
| sumN `i < n` | 270 ± 15 | 262 ± 9 | **3,787** ± 631 (14×) | 1,124 |
| saxpy | 242 ± 20 | 397 ± 113 | **2,259** ± 355 (9.3×) | 1,461 |
| jcopy | 186 ± 19 | 159 ± 10 | **1,351** ± 176 (7.3×) | 948 |
| sumLen `i < a.length` | 280 ± 35 | 299 ± 31 | **1,332** ± 201 (4.8×) | 901 |

- **The obvious flag does nothing.** `-XX:-RangeCheckElimination` alone gives
  **byte-identical** machine code in JDK 21, because loop predication has
  already hoisted the checks into predicates ahead of the loop. A failing
  predicate deoptimizes: `call UncommonTrapBlob ;*iaload`, with no slow loop.
  Only with predication also off do the checks stay in the loop, and then C2
  **stops vectorizing** (jcopy: 36 ymm ops → 0), as the hsdis listings show.
  This is the reverse of LLVM 20, which vectorizes around countable checks
  (finding 2).
- **jcopy** is vectorized by C2 (0.06 ns/elem) because `arraylength` is
  immutable. The same loop in C is 11.8× slower than unchecked because the
  length might alias the stores. `test/java-length.ll` shows that
  `!invariant.load` is what LLVM needs to be told.
- **stencil stays scalar in C2**, and my first hypothesis (aliasing) was
  wrong: a freshly allocated destination is still scalar. A bisect in C2
  assembly: `b[i] = 0.5*a[i]` vectorizes, while `a[i] + a[i+1]` and
  `a[i-1] + a[i]` don't. JDK 21's SuperWord gives up when one statement
  combines two references into the same array at different offsets.
- **Benchmarking slip, caught.** The first run had Java's `div` 2.5× faster
  than C. JMH had inlined the literal divisor 7, and C2 replaced `idiv` with a
  multiply. With the divisor in a field: 2,900 → ~9,300 ns/op.

This session ran with background load on the laptop (about 28% CPU), so
error bars are wide. Only the ≥ 4× effects above are claimed; gather, stencil
and div vary run to run.

## Layout
```
pass/RangeCheckVersioning.cpp   the pass (plugin: -passes=rce-version, or auto at VectorizerStart under -O2/-O3)
test/*.ll                       lit + FileCheck; test/difftest.c differential test
bench/kernels.c                 6 Java-style checked kernels, built checked / versioned / unchecked
missed/                         reduced tests and loops for findings 4-6
java/src/rce/                   the same kernels in Java + JMH + hsdis driver
scripts/{test,bench,perfstat,missed,java}.sh
results/                        every number quoted above, raw
docs/NOTES.md                   study notes: theory, how to read each listing, Q&A
```

## Reproduce (Linux / WSL2)
```bash
. scripts/env.sh        # LLVM 20 and perf (I extracted Ubuntu's debs without sudo; LLVM_ROOT/PERF override)
scripts/test.sh         # plugin build + lit + differential test   (what CI runs)
scripts/bench.sh        # timings + perf counters  (JCC=0 for the unpadded build)
scripts/missed.sh       # findings 4-6
scripts/java.sh         # hsdis build, C2 assembly, JMH x4
```

## What this is not
- **Not Alive2-verified.** Alive2 reasons about loops only by bounded
  unrolling, so it can't prove a versioning transform correct. The
  differential test is the substitute: it is empirical, not a proof.
- **Not IRCE.** It makes one all-or-nothing version per loop entry, with no
  pre/main/post splitting. It handles only innermost loops, and only checks
  whose block dominates the latch (`test/negative.ll` shows the misses with
  their remarks). Upstream IRCE does split the iteration space. It does not
  recognize the check once IndVarSimplify has rewritten it
  (`test/indvars-form.ll`), and without profile data it skips every loop as
  unprofitable.
- **No upstream contribution.** Two reduced cases are written up in
  [`missed/`](missed/) (findings 4 and 5). Both need checking against LLVM
  main before filing, and finding 4 is probably already fixed there.
- **No AArch64 hardware.** The SVE2 and Neoverse numbers are llvm-mca
  estimates.
- One laptop, under WSL2. Cycles are frequency-independent; ns figures are
  not. Run-to-run noise on these kernels is about ±5%, so smaller
  differences in the tables are not claimed.
