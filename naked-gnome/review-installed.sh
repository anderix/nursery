#!/usr/bin/env bash
# review-installed: list manually-installed packages by size, largest first,
# with a short synopsis for each. Use this to decide what to prune.
#
# Author: David Anderson (with AI assistance from Claude)

set -euo pipefail

manual=$(apt-mark showmanual)

dpkg-query -W -f='${Installed-Size}\t${Package}\t${binary:Summary}\n' \
  | awk -F'\t' -v manual="$manual" '
      BEGIN {
        n = split(manual, a, "\n")
        for (i = 1; i <= n; i++) m[a[i]] = 1
      }
      $2 in m
    ' \
  | sort -k1,1 -rn \
  | awk -F'\t' '
      {
        kb = $1
        total += kb
        if (kb >= 10240)      size = sprintf("%dM", kb/1024)
        else if (kb >= 1024)  size = sprintf("%.1fM", kb/1024)
        else                  size = sprintf("%dK", kb)
        printf "%-8s  %-32s  %s\n", size, $2, $3
      }
      END {
        if (total >= 1024) tsize = sprintf("%.1fM", total/1024)
        else               tsize = sprintf("%dK", total)
        printf "\n%-8s  %-32s  (%d packages)\n", tsize, "TOTAL", NR
      }
    '
