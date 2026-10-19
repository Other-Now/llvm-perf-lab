// Times every kernel in three builds (checked / versioned / unchecked).
// Output: CSV on stdout, one row per (kernel, n, variant).
//
// Methodology: each sample times `reps` back-to-back calls; the three
// variants are run in a rotated order every sample so no variant is always
// first (cold) or last (hot). Reported: median, min and max ns/element over
// the samples.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "kernels.h"

void bounds_fail(int64_t i, int64_t len) {
  fprintf(stderr, "bounds_fail(%lld, %lld) in benchmark\n", (long long)i, (long long)len);
  abort();
}

static double now_ns(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1e9 + t.tv_nsec;
}

static volatile int64_t g_sink;

typedef struct {
  int32_t n;
  int32_t *ia, *idx;
  float *fx, *fy;
  jarr *js, *jd;
} Data;

enum { NV = 3 };
static const char* VNAME[NV] = {"checked", "versioned", "unchecked"};

#define RUN3(call)                                         \
  switch (v) {                                             \
    case 0: g_sink += (int64_t)chk_##call; break;          \
    case 1: g_sink += (int64_t)ver_##call; break;          \
    default: g_sink += (int64_t)unc_##call; break;         \
  }
#define RUN3V(call)                                        \
  switch (v) {                                             \
    case 0: chk_##call; break;                             \
    case 1: ver_##call; break;                             \
    default: unc_##call; break;                            \
  }

static void run(int kernel, int v, Data* d) {
  int32_t n = d->n;
  switch (kernel) {
    case 0: RUN3(k_sum(d->ia, n, n)); break;
    case 1: RUN3V(k_saxpy(d->fy, n, d->fx, n, 1.0001f, n)); break;
    case 2: RUN3V(k_stencil(d->fy, n, d->fx, n, n)); break;
    case 3: RUN3(k_gather(d->ia, n, d->idx, n, n)); break;
    case 4: RUN3V(k_jcopy(d->jd, d->js, n)); break;
    default: RUN3(k_div(d->ia, n, 7, n)); break;
  }
}

static const char* KNAME[] = {"sum", "saxpy", "stencil", "gather", "jcopy", "div"};
enum { NK = 6 };

static int cmpd(const void* a, const void* b) {
  double x = *(const double*)a, y = *(const double*)b;
  return (x > y) - (x < y);
}

static int lookup(const char* s, const char** names, int count) {
  for (int i = 0; i < count; ++i)
    if (!strcmp(s, names[i])) return i;
  fprintf(stderr, "unknown name %s\n", s);
  exit(2);
}

static void fill(Data* d, int32_t n) {
  d->n = n;
  d->ia = malloc(n * sizeof(int32_t));
  d->idx = malloc(n * sizeof(int32_t));
  d->fx = malloc(n * sizeof(float));
  d->fy = malloc(n * sizeof(float));
  d->js = malloc(sizeof(jarr) + n * sizeof(int32_t));
  d->jd = malloc(sizeof(jarr) + n * sizeof(int32_t));
  d->js->len = d->jd->len = n;
  for (int32_t i = 0; i < n; ++i) {
    d->ia[i] = rand() % 1000;
    d->idx[i] = rand() % n;
    d->fx[i] = (float)(rand() % 100) / 7.f;
    d->fy[i] = 0.f;
    d->js->data[i] = d->ia[i];
  }
}

int main(int argc, char** argv) {
  srand(12345);
  // `bench one <kernel> <variant> <n> <reps>`: a single configuration, for
  // running under `perf stat`.
  if (argc == 6 && !strcmp(argv[1], "one")) {
    int k = lookup(argv[2], KNAME, NK), v = lookup(argv[3], VNAME, NV);
    Data d;
    fill(&d, atoi(argv[4]));
    long reps = atol(argv[5]);
    double t0 = now_ns();
    for (long r = 0; r < reps; ++r) run(k, v, &d);
    printf("%s,%d,%s,%.4f\n", argv[2], d.n, argv[3], (now_ns() - t0) / ((double)reps * d.n));
    return 0;
  }
  int samples = argc > 1 ? atoi(argv[1]) : 31;
  int32_t sizes[] = {3000, 1000000};
  printf("kernel,n,variant,median_ns_per_elem,min_ns_per_elem,max_ns_per_elem\n");
  for (unsigned si = 0; si < sizeof sizes / sizeof *sizes; ++si) {
    Data d;
    int32_t n = sizes[si];
    fill(&d, n);
    // ~2M element-visits per sample keeps a sample around a millisecond.
    int reps = (int)(2000000 / n) + 1;
    double* t = malloc(sizeof(double) * samples * NV);
    for (int k = 0; k < NK; ++k) {
      for (int v = 0; v < NV; ++v) run(k, v, &d);  // warm-up
      for (int s = 0; s < samples; ++s)
        for (int j = 0; j < NV; ++j) {
          int v = (s + j) % NV;
          double t0 = now_ns();
          for (int r = 0; r < reps; ++r) run(k, v, &d);
          t[v * samples + s] = (now_ns() - t0) / ((double)reps * n);
        }
      for (int v = 0; v < NV; ++v) {
        double* tv = t + v * samples;
        qsort(tv, samples, sizeof(double), cmpd);
        printf("%s,%d,%s,%.4f,%.4f,%.4f\n", KNAME[k], n, VNAME[v], tv[samples / 2], tv[0],
               tv[samples - 1]);
      }
      fflush(stdout);
    }
    free(t); free(d.ia); free(d.idx); free(d.fx); free(d.fy); free(d.js); free(d.jd);
  }
  return (int)(g_sink & 0);
}
