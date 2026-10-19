// gemm-lab's two inner loops, written portably (GCC/Clang vector extensions,
// no intrinsics) so the same source compiles for x86-64 and AArch64:
//
//   axpy     c[j] += a * b[j]           -- what clang auto-vectorizes; the
//                                          `tiled`/`simd` stages are this loop
//   micro8x8 an 8x8 tile of C held in registers across the k loop
//                                       -- gemm-lab's register-blocked kernel
//
// scripts/missed.sh extracts each loop body from the -S output and feeds it
// to llvm-mca, which reports the bottleneck resource per iteration.
// __builtin_memcpy, not <string.h>: the AArch64 build is freestanding (no sysroot here).

typedef float v8f __attribute__((vector_size(32)));

void axpy(float* restrict c, const float* restrict b, float a, int n) {
  for (int j = 0; j < n; ++j) c[j] += a * b[j];
}

static inline v8f load8(const float* p) { v8f v; __builtin_memcpy(&v, p, sizeof v); return v; }
static inline void store8(float* p, v8f v) { __builtin_memcpy(p, &v, sizeof v); }

// C[0..8, 0..8] += A[0..8, 0..kc] * B[0..kc, 0..8]; row strides lda/ldb/ldc.
void micro8x8(const float* restrict A, int lda, const float* restrict B, int ldb,
              float* restrict C, int ldc, int kc) {
  v8f c0 = load8(C + 0 * ldc), c1 = load8(C + 1 * ldc), c2 = load8(C + 2 * ldc),
      c3 = load8(C + 3 * ldc), c4 = load8(C + 4 * ldc), c5 = load8(C + 5 * ldc),
      c6 = load8(C + 6 * ldc), c7 = load8(C + 7 * ldc);
  for (int k = 0; k < kc; ++k) {
    v8f b = load8(B + k * ldb);
    c0 += A[0 * lda + k] * b; c1 += A[1 * lda + k] * b;
    c2 += A[2 * lda + k] * b; c3 += A[3 * lda + k] * b;
    c4 += A[4 * lda + k] * b; c5 += A[5 * lda + k] * b;
    c6 += A[6 * lda + k] * b; c7 += A[7 * lda + k] * b;
  }
  store8(C + 0 * ldc, c0); store8(C + 1 * ldc, c1); store8(C + 2 * ldc, c2);
  store8(C + 3 * ldc, c3); store8(C + 4 * ldc, c4); store8(C + 5 * ldc, c5);
  store8(C + 6 * ldc, c6); store8(C + 7 * ldc, c7);
}
