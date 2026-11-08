#!/usr/bin/env bash
# Reference lists the census is compared against. Downloaded, not vendored.
#   work/ios-keyboard-en.json  iOS 27.0 keyboard prediction blocklist, as
#                              recovered by Derik Kauffman (swipeblocked.com, MIT)
#   work/hunspell-en_US.dic    LibreOffice/Firefox-style Hunspell dictionary;
#                              entries flagged "!" are NOSUGGEST
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
curl -fsSL https://swipeblocked.com/data/lists/en.json -o work/ios-keyboard-en.json
curl -fsSL https://raw.githubusercontent.com/LibreOffice/dictionaries/4fa94195b8136364dd40bf2b0366a0fe32058899/en/en_US.dic \
  -o work/hunspell-en_US.dic
shasum -a 256 work/ios-keyboard-en.json work/hunspell-en_US.dic >&2
