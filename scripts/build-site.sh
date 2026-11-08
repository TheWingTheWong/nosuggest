#!/usr/bin/env bash
# Regenerate docs/data from a census directory (default: this Mac's version).
set -euo pipefail
cd "$(dirname "$0")/.."
DATA="${1:-data/$(sw_vers -productVersion)}"
swift build -c release >&2
bin=.build/release/nosuggest
[ -f work/ios-keyboard-en.json ] || ./scripts/fetch-comparisons.sh
[ -f lexicon/en.txt ] || ./scripts/fetch-lexicon.sh   # SCOWL sizes for the by-size figures
$bin report --data "$DATA" --out docs/data > "$DATA/summary-en.md"
$bin guesses $(grep -v '^#' data/specimens-en.txt) > docs/data/specimens-en.json
echo "wrote docs/data and $DATA/summary-en.md" >&2
