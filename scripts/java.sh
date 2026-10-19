#!/usr/bin/env bash
# HotSpot C2 side of the study (WSL/Linux).
#   1. builds hsdis (HotSpot's disassembler plugin) from the JDK's own
#      hsdis-capstone.c against libcapstone,
#   2. dumps the C2 machine code for every kernel,
#   3. runs JMH four ways: default, -RangeCheckElimination, -RangeCheckElimination
#      -UseLoopPredicate (checks really stay in the loop), and -UseSuperWord.
# Expects: JAVA_HOME (a Linux JDK 21), and libcapstone in $CAPSTONE (headers + .so).
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/env.sh

JAVA_HOME=${JAVA_HOME:-$HOME/jdk21}
CAPSTONE=${CAPSTONE:-$HOME/llvm20/root/usr}
JB=${JB:-$HOME/lpl-build/java}
OUT=${OUT:-results/java}
JMH_VER=1.37
mkdir -p "$JB/lib" "$JB/classes" "$OUT"

fetch() { [ -f "$JB/lib/$2" ] || curl -sSfL --retry 3 --connect-timeout 15 --max-time 120 "$1" -o "$JB/lib/$2"; }
M=https://repo1.maven.org/maven2
fetch $M/org/openjdk/jmh/jmh-core/$JMH_VER/jmh-core-$JMH_VER.jar jmh-core.jar
fetch $M/org/openjdk/jmh/jmh-generator-annprocess/$JMH_VER/jmh-generator-annprocess-$JMH_VER.jar jmh-ann.jar
fetch $M/net/sf/jopt-simple/jopt-simple/5.0.4/jopt-simple-5.0.4.jar jopt.jar
fetch $M/org/apache/commons/commons-math3/3.6.1/commons-math3-3.6.1.jar math3.jar
CP="$JB/lib/jmh-core.jar:$JB/lib/jopt.jar:$JB/lib/math3.jar"

# hsdis: one C file from the JDK sources, built against capstone.
if [ ! -f "$JB/hsdis-amd64.so" ]; then
  H=https://raw.githubusercontent.com/openjdk/jdk21u/master/src/utils/hsdis
  curl -sSfL --retry 3 --connect-timeout 15 --max-time 120 $H/capstone/hsdis-capstone.c -o "$JB/hsdis-capstone.c"
  curl -sSfL --retry 3 --connect-timeout 15 --max-time 120 $H/hsdis.h -o "$JB/hsdis.h"
  # CAPSTONE_ARCH/MODE are normally passed by the JDK build (make/Hsdis.gmk).
  gcc -O2 -shared -fPIC -DCAPSTONE_ARCH=CS_ARCH_X86 -DCAPSTONE_MODE=CS_MODE_64 -I"$JB" -I"$CAPSTONE/include" -I"$CAPSTONE/include/capstone" \
      "$JB/hsdis-capstone.c" -L"$CAPSTONE/lib/x86_64-linux-gnu" -lcapstone \
      -Wl,-rpath,"$CAPSTONE/lib/x86_64-linux-gnu" -o "$JB/hsdis-amd64.so"
fi

"$JAVA_HOME/bin/javac" -d "$JB/classes" -cp "$CP" -processorpath "$CP:$JB/lib/jmh-ann.jar" \
    java/src/rce/*.java

echo "== C2 assembly"
for m in sumLen sumN saxpy stencil stencilFresh scale pair pairBack gather jcopy div; do
  LD_LIBRARY_PATH="$JB:$LD_LIBRARY_PATH" "$JAVA_HOME/bin/java" -XX:+UnlockDiagnosticVMOptions \
      -XX:-TieredCompilation -XX:-UseOnStackReplacement -XX:CompileCommand=quiet -XX:CompileCommand=print,rce.Kernels::$m \
      -XX:PrintAssemblyOptions=intel -cp "$JB/classes" rce.AsmDriver > "$OUT/asm_$m.txt" 2>&1
  echo "  $m: $(grep -c . "$OUT/asm_$m.txt") lines"
done

echo "== JMH"
run_jmh() {  # $1 = label, rest = JVM flags
  local label=$1; shift
  "$JAVA_HOME/bin/java" -cp "$JB/classes:$CP" org.openjdk.jmh.Main "rce.KernelsBench" \
      -jvmArgsAppend "$*" -rf csv -rff "$OUT/jmh_$label.csv" > "$OUT/jmh_$label.log" 2>&1
  echo "  $label done"
}
run_jmh default -Xmx512m
run_jmh no_rce -Xmx512m -XX:-RangeCheckElimination   # JDK 21: same code as default (predication already hoisted the checks)
run_jmh no_rce_nopred -Xmx512m -XX:-RangeCheckElimination -XX:-UseLoopPredicate
run_jmh no_superword -Xmx512m -XX:-UseSuperWord
