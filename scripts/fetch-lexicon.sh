#!/usr/bin/env bash
# Build the English probe lexicon from SCOWL (Kevin Atkinson's Spell Checking
# Oriented Word Lists, http://wordlist.aspell.net/), pinned by version and hash.
#
#   lexicon/en.txt            words to probe: SCOWL size <= 70, letters only
#                             (word<TAB>SCOWL size, smaller size = more common)
#   lexicon/neighbors-en.txt  everything up to size 95, used only to decide
#                             whether a typo is ambiguous (bigger is stricter)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=2020.12.07
SHA256=5587667caa20c4891390c2d42dbb4d5c4c3f41bee77af1457ece3ba23fb859cc
URL="https://downloads.sourceforge.net/project/wordlist/SCOWL/$VERSION/scowl-$VERSION.tar.gz"

mkdir -p lexicon work
tarball="work/scowl-$VERSION.tar.gz"
if [ ! -f "$tarball" ]; then
  echo "downloading SCOWL $VERSION" >&2
  curl -fsSL "$URL" -o "$tarball"
fi
echo "$SHA256  $tarball" | shasum -a 256 -c - >&2
rm -rf "work/scowl-$VERSION" && tar xzf "$tarball" -C work
final="work/scowl-$VERSION/final"

families="english-words american-words british-words english-upper american-upper british-upper english-proper-names american-proper-names british-proper-names"
collect() { # max_size
  for fam in $families variant_1-words variant_2-words; do
    for f in "$final"/"$fam".*; do
      [ -e "$f" ] || continue
      size="${f##*.}"
      [ "$size" -le "$1" ] || continue
      case "$fam" in variant_*) [ "$1" -ge 95 ] || continue ;; esac
      iconv -f latin1 -t utf-8 "$f" | awk -v s="$size" '{print $0 "\t" s}'
    done
  done
}

# Probe set: letters only, at least 4 long; keep the smallest size per word.
# A capitalised word whose lowercase form is also listed ("Mark", "mark") is
# dropped: the lowercase probe covers it, and capitalised typos of common
# words behave oddly (the checker answers "Mrk" with sentence-case guesses).
collect 70 | awk -F'\t' '$1 ~ /^[A-Za-z]+$/ && length($1) >= 4' \
  | sort -t$'\t' -k1,1 -k2,2n | awk -F'\t' '!seen[$1]++' > work/probe-all.tsv
awk -F'\t' 'NR==FNR { if ($1 ~ /^[a-z]+$/) lower[$1]=1; next }
             !($1 !~ /^[a-z]/ && (tolower($1) in lower))' work/probe-all.tsv work/probe-all.tsv > lexicon/en.txt
collect 95 | cut -f1 | awk '/^[A-Za-z][A-Za-z'"'"'-]*$/' | sort -u > lexicon/neighbors-en.txt
cp "$final/../README" lexicon/SCOWL-README 2>/dev/null || true

echo "lexicon/en.txt: $(wc -l < lexicon/en.txt) words; neighbors: $(wc -l < lexicon/neighbors-en.txt)" >&2
