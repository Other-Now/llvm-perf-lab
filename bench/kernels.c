// Java-style checked kernels. Every array access is preceded by the check a
// JIT inserts for `a[i]`: `(unsigned)i >= (unsigned)a.length` -> throw.
//
// scripts/bench.sh compiles this file three times, once per symbol prefix:
//   chk_   clang -O3                                (checks as written)
//   ver_   clang -O3 -fpass-plugin=RangeCheckVersioning.so
//   unc_   clang -O3 -DNO_CHECKS                     (upper bound: no checks)
#include <stdint.h>
#include "jarr.h"

#ifndef NO_CHECKS
__attribute__((noinline, cold, noreturn)) void bounds_fail(int64_t i, int64_t len);
#define CHECK(i, len) \
  do { if ((uint32_t)(i) >= (uint32_t)(len)) bounds_fail((i), (len)); } while (0)
#else
#define CHECK(i, len) ((void)0)
#endif

#ifndef PFX
#define PFX chk_
#endif
#define CAT2(a, b) a##b
#define CAT(a, b) CAT2(a, b)
#define NAME(x) CAT(PFX, x)
#define K __attribute__((noinline))

// 1. Reduction, one check.
K int64_t NAME(k_sum)(const int32_t* a, int32_t alen, int32_t n) {
  int64_t s = 0;
  for (int32_t i = 0; i < n; ++i) { CHECK(i, alen); s += a[i]; }
  return s;
}

// 2. saxpy: two arrays, two checks, a store.
K void NAME(k_saxpy)(float* y, int32_t ylen, const float* x, int32_t xlen, float k, int32_t n) {
  for (int32_t i = 0; i < n; ++i) {
    CHECK(i, xlen); CHECK(i, ylen);
    y[i] += k * x[i];
  }
}

// 3. 3-point stencil: offset indices i-1, i, i+1.
K void NAME(k_stencil)(float* b, int32_t blen, const float* a, int32_t alen, int32_t n) {
  for (int32_t i = 1; i < n - 1; ++i) {
    CHECK(i - 1, alen); CHECK(i, alen); CHECK(i + 1, alen); CHECK(i, blen);
    b[i] = 0.25f * a[i - 1] + 0.5f * a[i] + 0.25f * a[i + 1];
  }
}

// 4. Gather: idx[i] is checked against idxlen (affine) and a[idx[i]] against
//    alen (data-dependent -- no exit count exists for it).
K int64_t NAME(k_gather)(const int32_t* a, int32_t alen, const int32_t* idx, int32_t idxlen, int32_t n) {
  int64_t s = 0;
  for (int32_t i = 0; i < n; ++i) {
    CHECK(i, idxlen);
    int32_t j = idx[i];
    CHECK(j, alen);
    s += a[j];
  }
  return s;
}

// 5. Java array layout: the length lives in memory next to the data, and the
//    loop stores int32s -- which TBAA cannot separate from the int32 length.
K void NAME(k_jcopy)(jarr* dst, const jarr* src, int32_t n) {
  for (int32_t i = 0; i < n; ++i) {
    CHECK(i, src->len); CHECK(i, dst->len);
    dst->data[i] = 3 * src->data[i];
  }
}

// 6. Scalar-only work (integer divide does not vectorize on x86): the check is
//    pure overhead on an already-scalar loop.
K int64_t NAME(k_div)(const int32_t* a, int32_t alen, int32_t d, int32_t n) {
  int64_t s = 0;
  for (int32_t i = 0; i < n; ++i) { CHECK(i, alen); s += a[i] / d; }
  return s;
}
