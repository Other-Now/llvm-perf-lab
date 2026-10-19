#pragma once
#include <stdint.h>
#include "jarr.h"

#define DECLARE_KERNELS(P)                                                          \
  int64_t P##k_sum(const int32_t*, int32_t, int32_t);                              \
  void P##k_saxpy(float*, int32_t, const float*, int32_t, float, int32_t);         \
  void P##k_stencil(float*, int32_t, const float*, int32_t, int32_t);              \
  int64_t P##k_gather(const int32_t*, int32_t, const int32_t*, int32_t, int32_t);  \
  void P##k_jcopy(jarr*, const jarr*, int32_t);                                    \
  int64_t P##k_div(const int32_t*, int32_t, int32_t, int32_t);

DECLARE_KERNELS(chk_)
DECLARE_KERNELS(ver_)
DECLARE_KERNELS(unc_)

// Defined by each driver: the checked kernels call it when a check fails.
__attribute__((noreturn)) void bounds_fail(int64_t i, int64_t len);
