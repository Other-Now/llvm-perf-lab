package rce;

/**
 * Warms every kernel until C2 compiles it, so scripts/java.sh can capture the
 * C2 machine code with -XX:CompileCommand=print (needs hsdis on the library path).
 */
public final class AsmDriver {
    public static void main(String[] args) {
        int n = 3000;
        int[] a = new int[n], idx = new int[n], dst = new int[n];
        float[] x = new float[n], y = new float[n];
        for (int i = 0; i < n; i++) { a[i] = i % 1000; idx[i] = (i * 7) % n; x[i] = i; }
        long sink = 0;
        for (int r = 0; r < 20_000; r++) {
            sink += Kernels.sumLen(a) + Kernels.sumN(a, n) + Kernels.gather(a, idx, n) + Kernels.div(a, 7, n);
            Kernels.saxpy(y, x, 1.0001f, n);
            Kernels.stencil(y, x, n);
            y[1] += Kernels.stencilFresh(x, n)[1];
            Kernels.scale(y, x, n);
            Kernels.pair(y, x, n);
            Kernels.pairBack(y, x, n);
            Kernels.jcopy(dst, a, n);
        }
        System.out.println("sink=" + sink + " " + y[5] + " " + dst[5]);
    }
}
