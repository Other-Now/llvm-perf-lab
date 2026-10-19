#!/usr/bin/env bash
# Hardware-counter pass over every (kernel, variant) at n=3000 (L1-resident).
# Each configuration runs REPS times as a fresh process; the median of each
# counter is reported. Cycles, not ns, are the primary metric: the laptop's
# clock moves with turbo/thermal state, core cycles do not.
#   uop sources: dsb = decoded-uop cache, mite = legacy decoders, ms = microcode
# Usage: scripts/perfstat.sh <bench-binary> <out.csv>
set -euo pipefail
. "$(dirname "$0")/env.sh"
BIN=$1; CSV=$2; REPS=${REPS:-5}
EV=cycles,instructions,idq.dsb_uops,idq.mite_uops,idq.ms_uops
TMP=$(mktemp -d)
echo "kernel,variant,cycles_per_elem,instr_per_elem,dsb_share,mite_share,ms_share" > "$CSV"
for k in sum saxpy stencil gather jcopy div; do
  for v in checked versioned unchecked; do
    for r in $(seq $REPS); do
      "$PERF" stat -x, -e $EV -o "$TMP/$r" "$BIN" one $k $v 3000 100000 > /dev/null
    done
    cat "$TMP"/[0-9]* | awk -F, -v k=$k -v v=$v -v n=300000000 '
      function med(a, cnt,  i, j, t) {
        for (i = 1; i <= cnt; i++) for (j = i + 1; j <= cnt; j++)
          if (a[j] < a[i]) { t = a[i]; a[i] = a[j]; a[j] = t }
        return a[int((cnt + 1) / 2)]
      }
      $3 ~ /^cycles/ {c[++nc]=$1} $3 ~ /^instructions/ {i[++ni]=$1}
      $3 ~ /dsb_uops/ {d[++nd]=$1} $3 ~ /mite_uops/ {m[++nm]=$1} $3 ~ /ms_uops/ {s[++ns]=$1}
      END {
        D = med(d, nd); M = med(m, nm); S = med(s, ns); T = D + M + S
        printf "%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f\n", k, v, med(c, nc)/n, med(i, ni)/n, D/T, M/T, S/T
      }'
  done
done | tee -a "$CSV"
rm -rf "$TMP"
