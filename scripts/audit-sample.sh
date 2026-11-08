#!/usr/bin/env bash
# Draw the audit samples that data/<version>/audit-*.tsv label by hand:
#   - every control word that missed all eight typos (an unbiased sample of the lexicon)
#   - 200 words drawn at random from the suppressed list (seeded, reproducible)
set -euo pipefail
cd "$(dirname "$0")/.."
DATA="${1:-data/$(sw_vers -productVersion)}"
jq -r 'select(.verdict=="suppressed") | .word' "$DATA/control-en.jsonl" | sort
echo "---"
jq -r 'select(.verdict=="suppressed") | .word' "$DATA/probe-en.jsonl" | sort \
  | awk 'BEGIN { srand(20261108) } { print rand() "\t" $0 }' | sort -n | head -200 | cut -f2 | sort
