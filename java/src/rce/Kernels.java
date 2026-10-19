package rce;

/**
 * The same six loop shapes as bench/kernels.c, in Java, where every array
 * access carries an implicit range check. HotSpot C2 decides per loop whether
 * to keep, hoist, or delete each one.
 */
public final class Kernels {
    private Kernels() {}

    /** Loop bound is the array's own length: the textbook case. */
    public static long sumLen(int[] a) {
        long s = 0;
        for (int i = 0; i < a.length; i++) s += a[i];
        return s;
    }

    /** Loop bound unrelated to the length: needs a runtime guard (loop predication / pre-main-post). */
    public static long sumN(int[] a, int n) {
        long s = 0;
        for (int i = 0; i < n; i++) s += a[i];
        return s;
    }

    public static void saxpy(float[] y, float[] x, float k, int n) {
        for (int i = 0; i < n; i++) y[i] += k * x[i];
    }

    public static void stencil(float[] b, float[] a, int n) {
        for (int i = 1; i < n - 1; i++) b[i] = 0.25f * a[i - 1] + 0.5f * a[i] + 0.25f * a[i + 1];
    }

    /**
     * stencil with a destination C2 can prove distinct from {@code a} (it was
     * just allocated). If {@link #stencil} stays scalar only because b and a
     * might be the same float[], this one vectorizes.
     */
    public static float[] stencilFresh(float[] a, int n) {
        float[] b = new float[n];
        for (int i = 1; i < n - 1; i++) b[i] = 0.25f * a[i - 1] + 0.5f * a[i] + 0.25f * a[i + 1];
        return b;
    }

    // Bisecting why C2 (JDK 21) leaves stencil scalar: one load per element,
    // then two loads of the same array at offsets 0/+1, then -1/0.
    public static void scale(float[] b, float[] a, int n) {
        for (int i = 1; i < n - 1; i++) b[i] = 0.5f * a[i];
    }

    public static void pair(float[] b, float[] a, int n) {
        for (int i = 1; i < n - 1; i++) b[i] = a[i] + a[i + 1];
    }

    public static void pairBack(float[] b, float[] a, int n) {
        for (int i = 1; i < n - 1; i++) b[i] = a[i - 1] + a[i];
    }

    /** a[idx[i]]: the second check depends on loaded data and cannot be hoisted. */
    public static long gather(int[] a, int[] idx, int n) {
        long s = 0;
        for (int i = 0; i < n; i++) s += a[idx[i]];
        return s;
    }

    /** The case LLVM could not touch in C: lengths live in memory next to stored-to data. */
    public static void jcopy(int[] dst, int[] src, int n) {
        for (int i = 0; i < n; i++) dst[i] = 3 * src[i];
    }

    public static long div(int[] a, int d, int n) {
        long s = 0;
        for (int i = 0; i < n; i++) s += a[i] / d;
        return s;
    }
}
