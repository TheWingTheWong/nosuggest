#!/usr/bin/env bash
# Draw the word samples that data/<version>/audit-*.tsv label by hand.
#   control-zeros  every control word that stage 1 flagged (an unbiased sample
#                  of the lexicon's zeros)
#   sample         200 words from the final list
#   base-rate      200 words the checker suggests, labelled with the same
#                  rubric, to show how often an ordinary word looks "topical"
# Order is by a Lehmer-style hash of seed+word modulo the prime 2^31-1,
# with extra multiply rounds so words sharing a prefix scatter. Every
# intermediate value stays below 2^53, so all awks (which use doubles)
# compute it exactly and draw the same sample.
set -euo pipefail
cd "$(dirname "$0")/.."
DATA="${1:-data/$(sw_vers -productVersion)}"
SEED=20261108

hashsort() {
  awk -v seed="$SEED" '
    BEGIN { for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i }
    {
      s = seed ":" $0; h = 7
      for (i = 1; i <= length(s); i++) h = ((h + ord[substr(s, i, 1)]) * 48271) % 2147483647
      for (r = 0; r < 16; r++) h = (h * 48271) % 2147483647
      printf "%010d\t%s\n", h, $0
    }' | sort | cut -f2
}

case "${2:-all}" in
  control-zeros) jq -r 'select(.verdict=="suppressed") | .word' "$DATA/control-en.jsonl" | sort ;;
  sample)        jq -r 'select(.verdict=="suppressed") | .word' "$DATA/verify-en.jsonl" | hashsort | head -200 | sort ;;
  base-rate)     jq -r 'select(.verdict=="suggested") | .word' "$DATA/probe-en.jsonl" | hashsort | head -200 | sort ;;
  *) echo "usage: $0 <data-dir> control-zeros|sample|base-rate" >&2; exit 2 ;;
esac
