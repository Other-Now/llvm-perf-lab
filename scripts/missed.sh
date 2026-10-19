#!/usr/bin/env bash
# Part 2: missed-optimization case studies. Writes everything to results/missed/.
#   A. LV interleave count vs trivially dead code   (missed/lv-dead-code-ic.ll)
#   B. histogram (vecagg-lab's loop) on AVX2 / AVX-512 / SVE2 (missed/hist.c)
#   C. gemm-lab's axpy vs register-blocked micro-kernel under llvm-mca,
#      cross-checked against perf cycles on this machine  (missed/gemm_inner.c)
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
OUT=${OUT:-results/missed}
W=${W:-$HOME/lpl-build/missed}
mkdir -p "$OUT" "$W"

ic() { opt -passes=loop-vectorize "${@:2}" -pass-remarks=loop-vectorize -disable-output "$1" 2>&1 |
       grep -oE "interleaved count: [0-9]+" | grep -oE "[0-9]+$" || echo none; }
with_dead() { awk -v line="$1" '/; DEAD/ { print "  " line; next } {print}' missed/lv-dead-code-ic.ll > "$W/d.ll"; }

echo "== A. dead code vs interleave count (LLVM $(llvm-config --version), skylake)"
{
  echo "dead_instruction,knob,interleave_count"
  for line in '; (none)' '%dead = add i64 %i, 7' '%dead = icmp ult i64 %i, %len' \
              '%dead = add i64 %len, 1' '%dead = fmul float %r, 3.0'; do
    with_dead "$line"
    for knob in default -force-target-num-vector-regs=64 instcombine-first; do
      case $knob in
        default) r=$(ic "$W/d.ll") ;;
        instcombine-first) opt -passes=instcombine "$W/d.ll" -o "$W/d2.bc"; r=$(ic "$W/d2.bc") ;;
        *) r=$(ic "$W/d.ll" $knob) ;;
      esac
      echo "\"$line\",$knob,$r"
    done
  done
} | tee "$OUT/dead_code_ic.csv"

echo "== B. histogram"
{
  for cfg in "x86_64-linux-gnu|-march=skylake|x86-avx2" \
             "x86_64-linux-gnu|-march=skylake-avx512|x86-avx512" \
             "x86_64-linux-gnu|-march=skylake-avx512 -mllvm -enable-histogram-loop-vectorization|x86-avx512+histflag" \
             "aarch64-linux-gnu|-march=armv9-a|sve2" \
             "aarch64-linux-gnu|-march=armv9-a -mllvm -enable-histogram-loop-vectorization|sve2+histflag"; do
    IFS='|' read -r tgt flags name <<< "$cfg"
    clang --target=$tgt $flags -O3 -ffreestanding -S missed/hist.c -o "$W/hist_$name.s" \
          -Rpass=loop-vectorize -Rpass-missed=loop-vectorize 2> "$W/hist_$name.rem"
    cp "$W/hist_$name.s" "$OUT/hist_$name.s"
    for fn in hist_count hist_count_sum; do
      line=$(grep -n "^void $fn(" missed/hist.c | head -1 | cut -d: -f1)
      v=$(grep -E "hist.c:$((line+1)):3: remark: vectorized" "$W/hist_$name.rem" | grep -oE "width: [^)]*" | head -1 || true)
      echo "$name,$fn,${v:-not vectorized},histcnt=$(grep -c histcnt "$W/hist_$name.s" || true)"
    done
  done
} | tee "$OUT/hist_summary.csv"


if [ -x "${PERF:-}" ]; then
  echo "== B2. histogram on this machine: default (scalar) vs -enable-histogram-loop-vectorization"
  for v in scalar vec; do
    f=""; [ $v = vec ] && f="-mllvm -enable-histogram-loop-vectorization"
    clang -O3 -march=native -mbranches-within-32B-boundaries $f -ffreestanding -Dhist_count=hist_count_$v \
          -Dhist_count_sum=hist_count_sum_$v -c missed/hist.c -o "$W/hist_$v.o" -Rpass=loop-vectorize 2>&1 |
      grep -oE "hist.c:12.*vectorized loop.*\)" || true
  done
  clang -O2 missed/hist_bench.c "$W/hist_scalar.o" "$W/hist_vec.o" -o "$W/hist_bench"
  {
    echo "variant,groups,cycles_per_row,instr_per_row"
    for g in 257 22754; do
      for v in scalar vec; do
        for rep in 1 2 3; do
          rows=$("$PERF" stat -x, -e cycles,instructions -o "$W/p.txt" "$W/hist_bench" $v $g 20000)
          awk -F, -v v=$v -v g=$g -v n=$rows '$3 ~ /^cycles/ {c=$1} $3 ~ /^instructions/ {i=$1}
            END {printf "%s,%s,%.3f,%.3f\n", v, g, c/n, i/n}' "$W/p.txt"
        done
      done
    done
  } | tee "$OUT/hist_perf.csv"
fi

mca() {  # $1 = .s  $2 = function  $3 = pattern  $4 = mca flags  -> summary lines
  awk -v FN="$2" -v PAT="$3" -f scripts/loop_body.awk "$1" > "$W/loop.s"
  llvm-mca $4 -iterations=200 -bottleneck-analysis "$W/loop.s" > "$W/mca.txt" 2>&1
  local insns cyc rthr
  insns=$(grep -c . "$W/loop.s")
  cyc=$(awk '/^Total Cycles:/ {print $3}' "$W/mca.txt")
  rthr=$(awk '/^Block RThroughput:/ {print $3}' "$W/mca.txt")
  echo "$insns,$(awk -v c=$cyc 'BEGIN{printf "%.2f", c/200}'),$rthr"
}

echo "== C. gemm inner loops: llvm-mca prediction vs perf"
{
  echo "target,kernel,loop_insns,mca_cycles_per_iter,mca_block_rthroughput,flops_per_iter,mca_flops_per_cycle"
  clang -O3 -march=skylake -S missed/gemm_inner.c -o "$OUT/gemm_inner_skylake.s"
  clang --target=aarch64-linux-gnu -mcpu=neoverse-v2 -O3 -ffreestanding -S missed/gemm_inner.c \
        -o "$OUT/gemm_inner_neoverse-v2.s"
  for cfg in "skylake|-mtriple=x86_64 -mcpu=skylake|vfmadd" \
             "neoverse-v2|-mtriple=aarch64 -mcpu=neoverse-v2|fmla"; do
    IFS='|' read -r t mflags pat <<< "$cfg"
    s="$OUT/gemm_inner_$t.s"
    # flops per loop iteration: axpy = 2 * (elements per iteration, from the
    # widest pointer increment); micro8x8 = 2 * 8 rows * 8 cols per k.
    r=$(mca "$s" axpy "$pat" "$mflags")
    awk -v FN=axpy -v PAT="$pat" -f scripts/loop_body.awk "$s" > "$OUT/loop_axpy_$t.s"
    nfma=$(grep -cE "$pat" "$OUT/loop_axpy_$t.s")
    lanes=$([ "$t" = skylake ] && echo 8 || echo 4)
    fl=$((2 * nfma * lanes))
    echo "$t,axpy,$r,$fl,$(awk -v r="$r" -v f=$fl 'BEGIN{split(r,a,","); printf "%.1f", f/a[2]}')"
    r=$(mca "$s" micro8x8 "$pat" "$mflags")
    awk -v FN=micro8x8 -v PAT="$pat" -f scripts/loop_body.awk "$s" > "$OUT/loop_micro8x8_$t.s"
    nfma=$(grep -cE "$pat" "$OUT/loop_micro8x8_$t.s")
    fl=$((2 * nfma * lanes))
    echo "$t,micro8x8,$r,$fl,$(awk -v r="$r" -v f=$fl 'BEGIN{split(r,a,","); printf "%.1f", f/a[2]}')"
    cp "$W/mca.txt" "$OUT/mca_micro8x8_$t.txt"
  done
} | tee "$OUT/gemm_mca.csv"

if [ -x "${PERF:-}" ]; then
  clang -O3 -march=native -mbranches-within-32B-boundaries missed/gemm_inner.c missed/gemm_bench.c -o "$W/gemm_bench"
  {
    echo "kernel,flops,cycles,measured_flops_per_cycle"
    for k in axpy micro; do
      for rep in 1 2 3; do
        fl=$("$PERF" stat -x, -e cycles -o "$W/p.txt" "$W/gemm_bench" $k 300000 | cut -d' ' -f1)
        cyc=$(awk -F, '$3 ~ /^cycles/ {print $1}' "$W/p.txt")
        echo "$k,$fl,$cyc,$(awk -v f=$fl -v c=$cyc 'BEGIN{printf "%.2f", f/c}')"
      done
    done
  } | tee "$OUT/gemm_perf.csv"
fi
