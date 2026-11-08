#!/usr/bin/env bash
# Full census on this Mac, in three steps:
#   1. every SCOWL word (size <= 70) through an eight-typo battery;
#   2. every word flagged in step 1 through its whole keyboard neighbourhood
#      (about 60 typos each); only words that survive are reported;
#   3. a full-battery control sample of random words.
# Takes about 35 minutes; the spell server is the bottleneck.
set -euo pipefail
cd "$(dirname "$0")/.."
JOBS="${JOBS:-4}"
LANG_CODE="${LANG_CODE:-en}"
OUT="${OUT:-data/$(sw_vers -productVersion)}"

[ -f lexicon/en.txt ] || ./scripts/fetch-lexicon.sh
swift build -c release >&2
bin=.build/release/nosuggest
mkdir -p "$OUT"

$bin env --language "$LANG_CODE" > "$OUT/env.json"
sw_vers > "$OUT/sw_vers.txt"
echo "census -> $OUT" >&2
time $bin probe --lexicon lexicon/en.txt --neighbors lexicon/neighbors-en.txt \
  --language "$LANG_CODE" --jobs "$JOBS" --out "$OUT/probe-$LANG_CODE.jsonl"
jq -r 'select(.verdict=="suppressed") | .word' "$OUT/probe-$LANG_CODE.jsonl" > "$OUT/flagged-$LANG_CODE.txt"
echo "verifying $(wc -l < "$OUT/flagged-$LANG_CODE.txt") flagged words" >&2
time $bin probe --lexicon "$OUT/flagged-$LANG_CODE.txt" --neighbors lexicon/neighbors-en.txt \
  --language "$LANG_CODE" --jobs "$JOBS" --neighbourhood 1 --out "$OUT/verify-$LANG_CODE.jsonl"
rm "$OUT/flagged-$LANG_CODE.txt"
time $bin control --lexicon lexicon/en.txt --neighbors lexicon/neighbors-en.txt \
  --language "$LANG_CODE" --sample "${SAMPLE:-3000}" --jobs "$JOBS" --out "$OUT/control-$LANG_CODE.jsonl"
gzip -kf "$OUT/probe-$LANG_CODE.jsonl"
gzip -kf "$OUT/verify-$LANG_CODE.jsonl"
echo "done" >&2
