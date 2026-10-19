#!/usr/bin/env bash
# Correctness only (no timing): build the plugin, run the lit/FileCheck suite,
# then the differential test of checked vs versioned kernels.
# Usage: scripts/test.sh [difftest-trials]
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh
BUILD=${BUILD:-$HOME/lpl-build}
export LPL_BUILD=$BUILD

cmake -S . -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_DIR="$LLVM_ROOT/lib/cmake/llvm" -DCMAKE_CXX_COMPILER=${CXX:-g++} >/dev/null
ninja -C "$BUILD"

$LIT -v test

mkdir -p "$BUILD/obj"
F="-O3 -march=${MARCH:-x86-64-v3}"
clang $F -DPFX=chk_ -c bench/kernels.c -o "$BUILD/obj/chk.o"
clang $F -DPFX=ver_ -fpass-plugin="$BUILD/RangeCheckVersioning.so" -c bench/kernels.c -o "$BUILD/obj/ver.o"
clang $F -DPFX=unc_ -DNO_CHECKS -c bench/kernels.c -o "$BUILD/obj/unc.o"
clang -O2 test/difftest.c "$BUILD"/obj/{chk,ver,unc}.o -o "$BUILD/difftest"
"$BUILD/difftest" "${1:-200000}"
