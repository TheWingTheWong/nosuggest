#!/usr/bin/env bash
# Full census on this Mac: every SCOWL word (size <= 70) through the system
# spell checker, then a full-battery control sample for error rates.
# Takes about 20-30 minutes; the spell server is the bottleneck.
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
time $bin control --lexicon lexicon/en.txt --neighbors lexicon/neighbors-en.txt \
  --language "$LANG_CODE" --sample "${SAMPLE:-3000}" --jobs "$JOBS" --out "$OUT/control-$LANG_CODE.jsonl"
gzip -kf "$OUT/probe-$LANG_CODE.jsonl"
echo "done" >&2
