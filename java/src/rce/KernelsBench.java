package rce;

import java.util.Random;
import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.annotations.*;

/**
 * JMH: ns per call at n = 3000 (same size as the C benchmark). Run three ways
 * by scripts/java.sh -- default C2, -XX:-RangeCheckElimination, and
 * -XX:-UseSuperWord -- to separate "the check costs something" from "the check
 * blocks vectorization".
 */
@State(Scope.Thread)
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@Warmup(iterations = 5, time = 200, timeUnit = TimeUnit.MILLISECONDS)
@Measurement(iterations = 10, time = 200, timeUnit = TimeUnit.MILLISECONDS)
@Fork(3)
public class KernelsBench {
    static final int N = 3000;
    int[] ia, idx, dst;
    float[] fx, fy;
    // Fields, not literals: once the kernel is inlined into the benchmark
    // method, a literal divisor lets C2 turn idiv into a multiply (the first
    // run did exactly that: div looked 2.5x faster than the C kernel).
    int n = N;
    int d = 7;

    @Setup
    public void setup() {
        Random r = new Random(12345);
        ia = new int[N]; idx = new int[N]; dst = new int[N];
        fx = new float[N]; fy = new float[N];
        for (int i = 0; i < N; i++) {
            ia[i] = r.nextInt(1000);
            idx[i] = r.nextInt(N);
            fx[i] = r.nextInt(100) / 7f;
        }
    }

    @Benchmark public long sumLen() { return Kernels.sumLen(ia); }
    @Benchmark public long sumN() { return Kernels.sumN(ia, n); }
    @Benchmark public float[] saxpy() { Kernels.saxpy(fy, fx, 1.0001f, n); return fy; }
    @Benchmark public float[] stencil() { Kernels.stencil(fy, fx, n); return fy; }
    @Benchmark public float[] stencilFresh() { return Kernels.stencilFresh(fx, n); }
    @Benchmark public long gather() { return Kernels.gather(ia, idx, n); }
    @Benchmark public int[] jcopy() { Kernels.jcopy(dst, ia, n); return dst; }
    @Benchmark public long div() { return Kernels.div(ia, d, n); }
}
