#!/usr/bin/env bash
# Re-probe 200 suppressed and 200 suggested words from a census and count
# how many verdicts come out the same.
set -euo pipefail
cd "$(dirname "$0")/.."
DATA="${1:-data/$(sw_vers -productVersion)}"
bin=.build/release/nosuggest
pick() { jq -r "select(.verdict==\"$1\")|.word" "$DATA/probe-en.jsonl" | awk -v s="$2" 'BEGIN{srand(s)}{print rand()"\t"$0}' | sort -n | head -200 | cut -f2; }
mkdir -p work
{ pick suppressed 1; pick suggested 2; } > work/stability.txt
$bin probe --jobs 4 --lexicon work/stability.txt --neighbors lexicon/neighbors-en.txt --out work/stability.jsonl 2>/dev/null
join -t$'\t' <(jq -r '"\(.word)\t\(.verdict)"' "$DATA/probe-en.jsonl" | sort) \
             <(jq -r '"\(.word)\t\(.verdict)"' work/stability.jsonl | sort) \
  | awk -F'\t' '{n++; if ($2==$3) a++; else print "changed:", $0} END {print a "/" n " verdicts identical"}'
