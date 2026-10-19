// vecagg-lab's inner loop, reduced: a GROUP BY's per-group COUNT is a
// histogram -- counts[keys[i]]++. Two lanes of one vector can hit the same
// bucket, so a plain gather/add/scatter is wrong; the vectorizer needs a
// conflict-aware form. scripts/missed.sh compiles this for three targets and
// keeps the remarks + asm:
//   x86-64 AVX2        (no scatter, no conflict detection)
//   x86-64 AVX-512     (has vpconflictd and scatter)
//   AArch64 SVE2       (has HISTCNT, built for exactly this)
#include <stdint.h>

void hist_count(int32_t* restrict counts, const int32_t* restrict keys, int n) {
  for (int i = 0; i < n; ++i) counts[keys[i]]++;
}

// COUNT and SUM together, as vecagg actually does.
void hist_count_sum(int32_t* restrict counts, int64_t* restrict sums,
                    const int32_t* restrict keys, const int64_t* restrict vals, int n) {
  for (int i = 0; i < n; ++i) {
    counts[keys[i]]++;
    sums[keys[i]] += vals[i];
  }
}
