// Times hist_count (missed/hist.c) built two ways and linked side by side:
// as LLVM 20 emits it by default (scalar) and with
// -enable-histogram-loop-vectorization (the "vectorized" form). Keys are
// uniform over GROUPS buckets; 257 matches vecagg-lab's low-cardinality run.
//   hist_bench <scalar|vec> <groups> <reps>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void hist_count_scalar(int32_t* restrict counts, const int32_t* restrict keys, int n);
void hist_count_vec(int32_t* restrict counts, const int32_t* restrict keys, int n);

int main(int argc, char** argv) {
  if (argc != 4) return 2;
  int groups = atoi(argv[2]);
  long reps = atol(argv[3]);
  enum { N = 4096 };
  static int32_t keys[N];
  int32_t* counts = calloc(groups, sizeof(int32_t));
  srand(7);
  for (int i = 0; i < N; ++i) keys[i] = rand() % groups;
  void (*f)(int32_t*, const int32_t*, int) =
      strcmp(argv[1], "vec") ? hist_count_scalar : hist_count_vec;
  for (long r = 0; r < reps; ++r) f(counts, keys, N);
  long total = 0;
  for (int g = 0; g < groups; ++g) total += counts[g];
  printf("%ld\n", (long)N * reps);
  return total != (long)N * reps;  // both builds must count every row
}
