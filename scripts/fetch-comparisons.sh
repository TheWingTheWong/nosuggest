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
# The Hunspell file is pinned by commit. Swipeblocked is a live site, so its
# list is checked against the copy the published census used and a change is
# reported rather than silently absorbed.
echo "f0b1a234bd178bdd01875b2a392a9647f888b8fe879f79c52aae62c2759b3647  work/hunspell-en_US.dic" | shasum -a 256 -c - >&2
if ! echo "1a6b7a1af156a9db07584b52083f20dc233412e053ed9975949df268bd880923  work/ios-keyboard-en.json" | shasum -a 256 -c - >/dev/null 2>&1; then
  echo "note: swipeblocked.com's English list has changed since the published census (2026-11-08)" >&2
fi
