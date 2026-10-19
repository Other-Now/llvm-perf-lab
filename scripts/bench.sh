#!/usr/bin/env bash
# Builds the kernels three ways, runs the differential test, the timings, and
# a perf-counter pass. Usage (WSL/Linux): scripts/bench.sh [samples] [trials]
#
#   JCC=0      build WITHOUT -mbranches-within-32B-boundaries (shows the
#              Skylake JCC-erratum placement artifact; see README)
#   OUT=dir    where results go (default results/)
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh

BUILD=${BUILD:-$HOME/lpl-build}
PLUGIN=$BUILD/RangeCheckVersioning.so
OUT=${OUT:-results}
MARCH=${MARCH:--march=native}
JCC=${JCC:-1}
CFLAGS="-O3 $MARCH -Wno-unused-command-line-argument"
[ "$JCC" = 1 ] && CFLAGS="$CFLAGS -mbranches-within-32B-boundaries"
mkdir -p "$BUILD/obj" "$OUT"

cmake -S . -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_DIR="$LLVM_ROOT/lib/cmake/llvm" -DCMAKE_CXX_COMPILER=g++ >/dev/null
ninja -C "$BUILD" >/dev/null

clang $CFLAGS -DPFX=chk_ -c bench/kernels.c -o "$BUILD/obj/chk.o"
clang $CFLAGS -DPFX=ver_ -fpass-plugin="$PLUGIN" -c bench/kernels.c -o "$BUILD/obj/ver.o" \
      -Rpass='rce-version|loop-vectorize' -Rpass-missed='rce-version|loop-vectorize' \
      2>&1 | grep remark | sed 's|^.*bench/||' > "$OUT/remarks_versioned.txt"
clang $CFLAGS -DPFX=unc_ -DNO_CHECKS -c bench/kernels.c -o "$BUILD/obj/unc.o"

# The bench driver is placed with the same padding so its own branches do not
# move the kernels around between configurations.
clang -O2 $CFLAGS test/difftest.c "$BUILD"/obj/{chk,ver,unc}.o -o "$BUILD/difftest"
clang -O2 $CFLAGS bench/main.c   "$BUILD"/obj/{chk,ver,unc}.o -o "$BUILD/bench"

echo "== differential test"
"$BUILD/difftest" "${2:-200000}" | tee "$OUT/difftest.txt"

echo "== timings (median of ${1:-31} rotated samples)"
"$BUILD/bench" "${1:-31}" | tee "$OUT/bench.csv"

if [ -x "${PERF:-}" ]; then
  echo "== perf counters (n=3000, 100k calls, median of ${REPS:-5} processes)"
  bash scripts/perfstat.sh "$BUILD/bench" "$OUT/perfstat.csv"
fi
