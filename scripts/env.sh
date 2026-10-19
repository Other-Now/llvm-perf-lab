# Source from WSL: puts the user-space LLVM 20 (extracted from Ubuntu debs, no sudo) on PATH.
export LLVM_ROOT=${LLVM_ROOT:-$HOME/llvm20/root/usr/lib/llvm-20}
export LD_LIBRARY_PATH=$HOME/llvm20/root/usr/lib/x86_64-linux-gnu:$LLVM_ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export PATH=$LLVM_ROOT/bin:$PATH
export LIT="python3 $LLVM_ROOT/build/utils/lit/lit.py"
# perf 6.8 from Ubuntu's linux-tools debs (also extracted without sudo); WSL2 exposes the PMU.
export PERF=${PERF:-$HOME/perf/root/usr/lib/linux-tools-6.8.0-146/perf}
export LD_LIBRARY_PATH=$HOME/perf/root/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
