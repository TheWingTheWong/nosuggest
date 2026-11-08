# nosuggest

[![Launch video](assets/launch.png)](assets/launch.mp4)

**The macOS spell checker accepts 1,755 English words as correctly
spelled but will not offer them as a correction from any keyboard-plausible
typo.** Type *suicde* and it has no suggestions at all, though it knows
*suicide*. *Aborion*, *murdr*, *Isalm*, *gospl* and *Hiter* get the same
treatment, while *lesbain*, *euthanasa*, *Chrstian* and *Stlin* come back right
away. nosuggest finds these words from the outside, through the public
`NSSpellChecker` API that TextEdit, Mail, Notes, Pages and Safari text fields
use. It tried eight typos on each of 108,930 accepted words, then every
keyboard-plausible typo (about 90 per word) on the 1,798 that never
came back, and kept only the words that still never came back. In a hand audit
of 200 of them, 96% have an obvious sensitive meaning; in the same audit of
200 words the checker *does* suggest, 13% do.

**Live explorer: https://thewingthewong.github.io/nosuggest/**

![Four typo pairs with the macOS spell checker's real answers, drawn as its spelling menu (first four guesses): Christian, Stalin, pistol and euthanasia come back; Islam, Hitler, bullet and suicide do not](assets/hero.png)

This week the Guardian reported on Apple's "grey list" of phrases the iPhone
keyboard won't predict, which Derik Kauffman recovered from iOS
([Swipeblocked](https://swipeblocked.com)). That list is made of two- to
six-word phrases and only affects predictions and swipe typing. The spell
checker's list is a separate mechanism: it works on single words, it covers
medicine, religion, crime and history as well as profanity, and
1,677 of the 1,755 words here don't appear in any of the
4,513 iOS entries at all.

## Results (macOS 26.5.1, build 25F80, English)

Two passes over SCOWL's 128,780 most common English words (size 70 and
below):

| | words | typos tried |
|---|---:|---:|
| tested (the checker accepts the word) | 108,930 | 123,703 |
| flagged by pass 1 (0 of 6-8 typos came back) | 1,798 | |
| cleared by pass 2 (some typo brought the word, or another form of it, back) | 43 | 161,363 |
| **final list** | **1,755** | |

Also in pass 1: 107,042 words came back, 83 came back only as
another form (*Bostns* gives *Boston's*), 19,719 SCOWL words are flagged as
misspelled by the checker itself and 131 were untestable (internal capitals
like *BigQuery*).

Pass 2 cleared 43 words in three ways. 19 came back from some typo outside
the first eight, mostly first names and odd words (*carvry* gives *carvery*, *dieties* gives *deities*, *drunkeness* gives *drunkenness*, *Katheine* gives *Kathrine*).
24 came back only as another form of the word on two or more typos (*holocautss*
gives *holocaust*). Pass 1 had already sent 83 words the same way. Only words that no
keyboard-plausible typo returns, in any form, are on the list.

Of the 1,755 words on the final list:

- **70.8%** of their typos got an empty guess list, not merely a list
  without the word. Asked about *suicde*, *aborion*, *murdr* or *Isalm*, the
  checker says "No Guesses Found".
- **All 1,755** are also missing from completions of their own prefix, and
  none is ever produced by autocorrect. (A word autocorrect does produce, like
  *Mollie*, counts as offered and is not on the list.)
- **1,733** missed on two or more typos that have no other SCOWL word
  within one edit.
- 1,647 are lowercase; 108 are capitalised (*Hitler*, *Auschwitz*, *Islam*, *Satan*, *Shiite*, *Viagra*).
- Rarity doesn't explain it. By SCOWL size (10 is the most common words, 70
  the rarest in the census) the share on the list is
  0.1% at 10, 1.1% at 20, 1.8% at 35, 5.1% at 40, 1.5% at 50, 3.9% at 55, 1.3% at 60, 0.8% at 70. The
  rarest tier has one of the lowest rates.

By editorial category (rules in [`data/categories.tsv`](data/categories.tsv), applied
after the fact; not Apple's):

| category | words | examples |
|---|---:|---|
| sex and the body | 596 | *penis*, *vagina*, *arousal*, *bisexual*, *titillate* |
| profanity and insults | 266 | the usual, plus *redneck*, *dammit* |
| violence, crime and weapons | 232 | *murder*, *rape*, *bullet*, *abduct*, *behead*, *hijack* |
| death and medicine | 142 | *suicide*, *autopsy*, *amputee*, *cervix*, *chlamydia*, *urine* |
| religion | 102 | *Islam*, *gospel*, *psalms*, *sacrament*, *Satan*, *sharia*, *jihad* |
| slurs | 99 | (not reproduced here; blurred by default on the live page) |
| race and ethnicity | 83 | *Arab*, *Aryan*, *ghetto*, *skinhead* |
| drugs and alcohol | 75 | *cocaine*, *cannabis*, *marijuana*, *morphine* |
| nazism and hate groups | 49 | *Hitler*, *Nazi*, *Auschwitz*, *gestapo*, *swastika*, *fascism* |
| reproductive health | 34 | *abortion*, *condom*, *afterbirth*, *circumcision* |
| politics | 2 | *Syria*, *Hussein* |
| lookalikes | 26 | spelled like a sensitive word: *rapeseed*, *virginals* |
| names and places | 16 | capitalised words no rule covers |
| other | 33 | no sensitive reading found: *maroon*, *extern*, *rabidness* |

Some contrasts, checked with `nosuggest word`: *Stalin* is suggested and
*Hitler* is not; *Christian* and *Muslim* are suggested and *Islam* is not;
*pistol* and *firearm* are, *bullet* is not; *euthanasia*, *overdose*, *tampon*,
*contraception* and *lesbian* are suggested, *suicide*, *abortion* and *condom*
are not. Political names are mostly left alone: *Trump*, *Putin*, *Tibet*,
*Taiwan*, *Kashmir*, *Palestine* and *Gaza* are suggested (they were probed
separately, as most aren't in SCOWL); *Syria* and *Hussein* are not. The iOS
keyboard list, by contrast, is full of political phrases.

Hunspell, the open-source checker in LibreOffice, marks 27 entries in its
`en_US` dictionary `NOSUGGEST`, all profanity or slurs. On macOS, 23 of them
are on the final list, 2 are rejected as misspellings, 1 is borderline, 1 is not
in SCOWL and 0 are suggested.

## Every language has its own list

The same 25 concepts, translated into seven of the roughly forty languages the
Mac checks, each probed with every keyboard-plausible typo (about 82 per
word). Red means accepted but never suggested.

![Seven-language matrix](assets/matrix.png)

67 of the 175 cells are suppressed. Suppressed in every language: *vagina*, *marijuana*, *Hitler*, *Nazi*.
Nearly every cell is all or nothing: 172 of the 175 came back from every typo or from
none. *Islam* is suppressed in six languages (not Portuguese, where *islã* comes
back) and *gay* in five (not German or French). The rest varies: *abortion* only
in English and Spanish; *suicide* in English, German and French (in Spanish
only another form comes back); *cocaine* in English, German and Spanish; *Stalin* only in German; *lesbian*, *tampon* and
*Muslim* only in Spanish. Dutch suppresses *kanker* (cancer), which is also one
of the commonest Dutch swear words. Inconclusive cells are in italics on the
[live page](https://thewingthewong.github.io/nosuggest/); the related-form rule
is English-only, so in other languages it can mislabel a cell as inconclusive
(Spanish *cristiano* comes back from none of its typos but is marked related).

## Quickstart

Needs a Mac with Xcode or the Command Line Tools. No other dependencies.

```
git clone https://github.com/TheWingTheWong/nosuggest && cd nosuggest
swift run -c release nosuggest word suicide lesbian
```

```
suicide  ->  SUPPRESSED   (0/8 typos brought it back)
   no  suiide deletion [suite, suited]
   no  suciide transposition [succeed]
   no  suidide substitution []
   no  suiccide insertion []
   no  sucide deletion [succeed]
   no  suiicde transposition []
   no  sujcide substitution []
   no  suiicide insertion []
  completions of "suicid" include it: no
  autocorrect ever produces it: no

lesbian  ->  SUGGESTED   (8/8 typos brought it back)
  yes  lesian deletion [lesbian, lesion, Lesia]
  yes  lebsian transposition [lesbian]
  yes  lesfian substitution [lesbian]
  yes  lesbbian insertion [lesbian]
  yes  lebian deletion [lesbian, Debian]
  yes  lesiban transposition [lesbian]
  yes  leabian substitution [lesbian]
  yes  lessbian insertion [lesbian]
```

The full census downloads the SCOWL word lists (pinned by hash), runs both
passes and the control sample. It takes about 45 minutes, because the system
spell server answers about 175 guesses a second however many clients ask:

```
./scripts/run-census.sh          # -> data/<your macOS version>/
./scripts/build-site.sh          # -> docs/data/ and data/<version>/summary-en.md
swift run -c release nosuggest concepts > docs/data/concepts.json
```

Other commands: `nosuggest guesses suicde=suicide` prints the checker's raw
answers as JSON; `nosuggest probe --lexicon words.txt` runs your own list
(`--neighbourhood 1` for the exhaustive pass); `--language de` switches language.

## How it works

**Pass 1.** For each word the checker accepts, nosuggest builds eight one-edit
typos that a person might make, cycling through a deleted letter, two letters
swapped, a neighbouring QWERTY key and a doubled letter, starting from the
middle of the word. It never touches the first letter, because spell checkers
rely on it heavily. A typo the checker itself accepts as a word (*form* for
*from*) is skipped, because it tests nothing. Each remaining typo goes to
`guesses(forWordRange:in:language:inSpellDocumentWithTag:)` with an explicit
language and automatic language detection off. The probe stops at the first
typo that brings the word back.

**Pass 2.** Every word pass 1 flagged is tried again with its whole keyboard
neighbourhood: every interior deletion and transposition, a substitution by
every QWERTY neighbour, and an insertion of the same letter or a neighbouring
key at every position. That is about six typos per letter.

**Related forms.** If, on two or more typos, the checker answers with another
form of the word that is *further* from the typo than the word itself (*Bostns*
gives *Boston's* instead of *Bostons*), the word is labelled **related**, not
suppressed: the checker found the right family and ranked the wrong member.
"Another form" is narrow on purpose: plural and possessive endings (with
English's real *-es* rule) and *-ed*/*-ing*. Derivational suffixes and undoing a
doubled consonant don't count, because they make unrelated words look like
family (*raped*/*rapped*, *terrorism*/*terror's*, *slaves*/*Slavs*). A related form
that is itself one edit from the typo (*suicied* gives *suicided*) is a
competitor and clears nothing.

**The control.** Eight typos, no early stop, on 3,000 random lexicon words
(2,264 lowercase and 244 capitalised that the checker accepts). Over every
typo of every lowercase control word, 97.3% brought the word back. Among
words that came back at least once, 99.6% did, ranging by kind of typo from
99.2% to 99.8%.

![Control histogram](assets/control.svg)

The histogram (lowercase words) is bimodal: 2,189 words came back from all eight
typos, 52 from none, and 23 sit in between. The ones in between are odd
plurals and rare forms (*blockings*, *whitebaits*, *muchnesses*), the kind of
word pass 2 exists to clear.

**The audit.** Neither pass can say whether a zero is deliberate, so I
labelled three samples by hand with one rubric (obvious sensitive meaning;
spelled like one; no apparent reason) and published the labels in
[`data/26.5.1/`](data/26.5.1/):

| sample | n | sensitive meaning | lookalike | no apparent reason |
|---|---:|---:|---:|---:|
| random words from the final list | 200 | 191 (96%) | 4 | 5 (2.5%, 95% CI 1.1%-5.7%) |
| control words flagged by pass 1 | 53 | 48 | 4 | 1 |
| random words the checker suggests (base rate) | 200 | 26 (13%) | 1 | 173 |

The rubric is generous on purpose, in both directions: *whites*, *paramedics*
and *obits* count as sensitive in the base-rate sample, and *ream*, *chicks*,
*crone* and *Judaic* count in the list sample. It is one person's judgement,
made knowing which sample each word came from, with no second rater. A strict
reader would move some words in both samples to "no apparent reason"; the
base rate is there so the 96% figure has something to be compared with.
Projected over the list, about 44 words (95% CI 19-100) have no apparent
reason; the ones in the sample are *cootie*, *jivey*, *nautch*, *rabidness*, *undead*.

## Design decisions and trade-offs

- **Black box, not reverse engineering.** The iOS list was recovered by
  decoding Apple's hash tables, which is exact but has to be redone whenever
  the format changes. nosuggest only uses public AppKit API, so anyone can
  rerun it on any macOS version and diff the result. The cost is that it can
  only find words that are in its input list, and it can't see *why* a word is
  suppressed.
- **Errors pushed toward "suggested".** Case-insensitive matching (if
  *Suicide* were offered for *suicde*, that would count), the related-form
  rule, autocorrect and completion counting as offers, and a second pass that
  clears a word on a single hit out of about 90 all favour leaving a word off
  the list, so it is more likely an undercount than an overcount. It can
  still contain words the checker would return from a typo outside its
  neighbourhood (a typo in the first letter, or two edits away).
- **Two passes instead of one big one.** The full neighbourhood on all
  108,930 words would take about 15 hours at the spell server's rate. Eight typos
  settle 98% of words in 20 minutes; the exhaustive pass then only runs where
  it matters.
- **Child processes, not threads.** `NSSpellChecker` is not documented as
  thread-safe, and the spell server is the bottleneck anyway: one client gets
  about 100 guesses a second, four get about 175 between them. `--jobs` splits
  the lexicon round-robin across child processes.
- **Swift, AppKit only.** No dependencies. The probing logic lives in
  `NoSuggestCore`, which has no AppKit import and is tested against a
  simulated checker with known ground truth.

## Tests

`swift test` runs 28 tests. The property tests run over seeded random inputs:

- every typo in every pass-1 battery and every pass-2 neighbourhood is exactly
  one optimal-string-alignment edit from its source and keeps the first letter;
- `allEdits` equals the distance-one neighbourhood, checked in both
  directions;
- with a simulated checker that drops 30% of correct candidates independently,
  pass 1 flags every planted word, exactly, and at most 2 of about 11,000
  ordinary ones;
- with a simulated checker that ranks out 200 "hard" words on 75% of typos
  (the real failure mode: a whole word that is rarely offered), pass 1 is
  fooled by many of them, pass 2 clears all but at most 2, and no planted word
  is ever cleared;
- the related-form rule accepts real inflections (*Bostons*/*Boston's*,
  *bared*/*bare*), rejects the lookalikes the real checker returned for
  suppressed words (*Hitler*/*Hitter*, *suicide*/*suited*), rejects 13 false
  families the checker's real answers produced under an earlier, looser rule
  (*raped*/*rapped*, *slaves*/*Slavs*, *terrorism*/*terror's*), and ignores a related
  form that is itself one edit from the typo (*suicided* for *suicied*);
- a word autocorrect produces is never reported as suppressed;
- the audit parser counts labels and computes a Wilson interval.

CI builds and tests on a GitHub macOS runner, runs a live probe against that
runner's spell checker, and runs `nosuggest check-readme`, which fails if one
of about thirty numbers in this README (counts, rates, audit shares, every
category row) doesn't match `docs/data/summary-en.json`.

## Limitations

- **Input-bounded.** Only SCOWL words (size 70 and below) were probed. Slang,
  new coinages and most names aren't there. Words shorter than four letters
  (*sex*, *gay*) were left out of the census, because their typos collide with
  too many other words. `nosuggest word` will probe them: *gay* comes back from none of 6
  typos and *sex* from none of 5, one short of the census's bar.
- **The neighbourhood is finite.** First-letter typos and two-edit typos are
  never tried, so a listed word might still come back from one of those.
- **One machine, one version.** This census is macOS 26.5.1 (25F80), the
  version on the machine that ran it; macOS 27 was not tested. iOS's
  `UITextChecker` likely shares the engine but was not tested either.
- **Repeatability.** A rerun of 400 words (200 from each side of pass 1) with
  the same typos gave identical verdicts (400 of 400), which shows the checker is
  deterministic. That does not show the verdicts are robust to the choice of
  typos; pass 2 is the check for that.
- **The categories and the audit labels are mine.** They are applied after the
  fact to make the list browsable and to put a number on "is this deliberate".
  Apple's own grouping, if there is one, isn't visible from outside.

## Data

- `data/26.5.1/suppressed-en.txt`: the final list, one word per line.
- `data/26.5.1/probe-en.jsonl.gz`: pass 1, every word and typo, with the
  first eight guesses for each typo (the hit and related verdicts were made
  on the full guess list).
- `data/26.5.1/verify-en.jsonl.gz`: pass 2, every flagged word with its whole neighbourhood, same format.
- `data/26.5.1/stability-en.txt`: the 400-word rerun.

The census was produced by `scripts/run-census.sh`. After it ran, the
related-form rule was tightened (see the commit log). The new rule is strictly
narrower, so it can only change the verdict of a word that was labelled
"related" or that autocorrect produces; those 266 words were re-probed with the
new code and merged in. Every other verdict is what a full rerun gives, because
the checker is deterministic.
- `data/26.5.1/control-en.jsonl`: the control sample.
- `data/26.5.1/audit-*.tsv`: the hand labels.
- `data/26.5.1/summary-en.md`: every number in this README.
- `docs/data/`: what the explorer loads.

## References

- The Guardian, ["Struggling to spell 'male chauvinist pig'? Apple's grey list
  means your iPhone won't help you"](https://www.theguardian.com/technology/2026/nov/06/struggling-to-spell-male-chauvinist-pig-apple-grey-list-means-your-iphone-wont-help-you),
  6 November 2026.
- Derik Kauffman, [Swipeblocked](https://swipeblocked.com) and
  [github.com/derikk/swipeblocked](https://github.com/derikk/swipeblocked):
  the iOS keyboard blocklist, recovered from iOS 27.0.
- Kevin Atkinson, [SCOWL](http://wordlist.aspell.net/) (Spell Checking
  Oriented Word Lists), version 2020.12.07.
- Hunspell `en_US` dictionary as shipped by
  [LibreOffice](https://github.com/LibreOffice/dictionaries), whose `NOSUGGEST`
  flag does the same job in the open.
- Apple, [`NSSpellChecker`](https://developer.apple.com/documentation/appkit/nsspellchecker).

## License

MIT. The word lists are downloaded at run time and keep their own licenses.
