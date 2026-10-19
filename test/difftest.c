// Differential test: the versioned build must behave *exactly* like the
// checked build -- same return value, same memory afterwards, and when a check
// fails, the same failing (index, length) after the same partial side effects.
// That last part is the "precise exception" property a Java JIT must keep.
//
// Lengths and trip counts are drawn so that roughly half the trials fail a
// check somewhere (including negative lengths, which compare as huge unsigned
// values and so never fail, and n <= 2 for the stencil's empty loop).
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../bench/kernels.h"

static jmp_buf g_jb;
static int64_t g_fail_i, g_fail_len;

void bounds_fail(int64_t i, int64_t len) {
  g_fail_i = i;
  g_fail_len = len;
  longjmp(g_jb, 1);
}

enum { CAP = 600 };

typedef struct {
  int failed;
  int64_t fi, flen, ret;
  float fy[CAP];
  int32_t jd[CAP];
} Outcome;

typedef struct {
  int32_t n, l1, l2;
  int32_t ia[CAP], idx[CAP];
  float fx[CAP], fy0[CAP];
  int32_t js[CAP];
} Input;

static unsigned rnd(void) { return (unsigned)rand(); }
static int32_t pick_len(void) {
  switch (rnd() % 8) {
    case 0: return -(int32_t)(rnd() % 5) - 1;   // negative: never fails
    case 1: return 0;
    default: return (int32_t)(rnd() % 520);
  }
}

static jarr* mkjarr(int32_t len, const int32_t* src) {
  jarr* a = malloc(sizeof(jarr) + CAP * sizeof(int32_t));
  a->len = len;
  memcpy(a->data, src, CAP * sizeof(int32_t));
  return a;
}

static void run(int k, int ver, const Input* in, Outcome* o) {
  memset(o, 0, sizeof *o);
  memcpy(o->fy, in->fy0, sizeof o->fy);
  jarr* js = mkjarr(in->l1, in->js);
  jarr* jd = mkjarr(in->l2, in->js);
  memset(jd->data, 0, CAP * sizeof(int32_t));
  if (setjmp(g_jb)) {
    o->failed = 1;
    o->fi = g_fail_i;
    o->flen = g_fail_len;
  } else {
    int32_t n = in->n, l1 = in->l1, l2 = in->l2;
    switch (k) {
      case 0: o->ret = ver ? ver_k_sum(in->ia, l1, n) : chk_k_sum(in->ia, l1, n); break;
      case 1: ver ? ver_k_saxpy(o->fy, l1, in->fx, l2, 1.5f, n)
                  : chk_k_saxpy(o->fy, l1, in->fx, l2, 1.5f, n); break;
      case 2: ver ? ver_k_stencil(o->fy, l1, in->fx, l2, n)
                  : chk_k_stencil(o->fy, l1, in->fx, l2, n); break;
      case 3: o->ret = ver ? ver_k_gather(in->ia, l1, in->idx, l2, n)
                           : chk_k_gather(in->ia, l1, in->idx, l2, n); break;
      case 4: ver ? ver_k_jcopy(jd, js, n) : chk_k_jcopy(jd, js, n); break;
      default: o->ret = ver ? ver_k_div(in->ia, l1, 3, n) : chk_k_div(in->ia, l1, 3, n); break;
    }
  }
  memcpy(o->jd, jd->data, sizeof o->jd);
  free(js);
  free(jd);
}

int main(int argc, char** argv) {
  long trials = argc > 1 ? atol(argv[1]) : 200000;
  srand(argc > 2 ? atoi(argv[2]) : 1);
  static const char* names[] = {"sum", "saxpy", "stencil", "gather", "jcopy", "div"};
  long fails[6] = {0}, mismatches = 0;
  static Input in;
  static Outcome a, b;
  for (long t = 0; t < trials; ++t) {
    in.n = (int32_t)(rnd() % 520) - 4;  // includes n <= 0
    in.l1 = pick_len();
    in.l2 = pick_len();
    for (int i = 0; i < CAP; ++i) {
      in.ia[i] = (int32_t)(rnd() % 2001) - 1000;
      in.idx[i] = (int32_t)(rnd() % 560) - 20;  // some out of range, some negative
      in.fx[i] = (float)(rnd() % 1000) / 8.f;
      in.fy0[i] = (float)(rnd() % 1000) / 16.f;
      in.js[i] = in.ia[i];
    }
    for (int k = 0; k < 6; ++k) {
      run(k, 0, &in, &a);
      run(k, 1, &in, &b);
      fails[k] += a.failed;
      if (memcmp(&a, &b, sizeof a) != 0) {
        if (++mismatches <= 10)
          fprintf(stderr,
                  "MISMATCH %s n=%d l1=%d l2=%d: chk(failed=%d i=%lld ret=%lld) "
                  "ver(failed=%d i=%lld ret=%lld)\n",
                  names[k], in.n, in.l1, in.l2, a.failed, (long long)a.fi, (long long)a.ret,
                  b.failed, (long long)b.fi, (long long)b.ret);
      }
    }
  }
  printf("trials=%ld mismatches=%ld\n", trials, mismatches);
  for (int k = 0; k < 6; ++k)
    printf("  %-8s checked build trapped in %ld of %ld trials\n", names[k], fails[k], trials);
  return mismatches != 0;
}
