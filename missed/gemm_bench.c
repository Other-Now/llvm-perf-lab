// Measures the two gemm_inner.c loops on this machine, L1-resident, so that
// llvm-mca's predicted cycles/iteration can be checked against perf's cycles.
//   gemm_bench axpy  <reps>   : axpy over n=1024 floats (8 KB for b + c)
//   gemm_bench micro <reps>   : micro8x8 with kc=256 (B panel 8 KB, A 8 KB)
//   gemm_bench axpy_indexed / axpy_simple <reps> : the axpy_addr.S twins
// Prints FLOPs performed so the caller can divide by perf's cycle count.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void axpy(float* restrict c, const float* restrict b, float a, int n);
void micro8x8(const float* restrict A, int lda, const float* restrict B, int ldb,
              float* restrict C, int ldc, int kc);
void axpy_indexed(float* c, const float* b, float a, int n);  // axpy_addr.S
void axpy_simple(float* c, const float* b, float a, int n);

int main(int argc, char** argv) {
  if (argc != 3) return 2;
  long reps = atol(argv[2]);
  static float A[8 * 256], B[256 * 8], C[8 * 8], b[1024], c[1024];
  for (int i = 0; i < 2048; ++i) A[i] = B[i] = 1e-3f * (i % 7);
  for (int i = 0; i < 1024; ++i) b[i] = 1e-3f * (i % 5);
  double flops;
  if (!strcmp(argv[1], "axpy")) {
    for (long r = 0; r < reps; ++r) axpy(c, b, 1e-6f, 1024);
    flops = 2.0 * 1024 * reps;
  } else if (!strcmp(argv[1], "axpy_indexed")) {
    for (long r = 0; r < reps; ++r) axpy_indexed(c, b, 1e-6f, 1024);
    flops = 2.0 * 1024 * reps;
  } else if (!strcmp(argv[1], "axpy_simple")) {
    for (long r = 0; r < reps; ++r) axpy_simple(c, b, 1e-6f, 1024);
    flops = 2.0 * 1024 * reps;
  } else {
    for (long r = 0; r < reps; ++r) micro8x8(A, 256, B, 8, C, 8, 256);
    flops = 2.0 * 64 * 256 * reps;
  }
  printf("%.0f %g %g\n", flops, c[3], C[3]);
  return 0;
}
