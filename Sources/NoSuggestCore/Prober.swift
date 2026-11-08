import Foundation


/// The black-box probe: is a word that the spell checker accepts ever offered
/// back as a correction for a one-letter typo of itself?

/// The four questions the probe asks a spell checker. `AppleSpellOracle`
/// answers them with NSSpellChecker; tests answer them with a simulated
/// checker whose ground truth is known.
public protocol SpellOracle {
    /// True if the checker considers `word` correctly spelled.
    func isAccepted(_ word: String) -> Bool
    /// Ranked spelling guesses for a misspelled word.
    func guesses(for typo: String) -> [String]
    /// Completions the checker offers for a prefix.
    func completions(for prefix: String) -> [String]
    /// The single autocorrection the checker would apply, if any.
    func correction(for typo: String) -> String?
}

/// A set of known words used to judge whether a typo is ambiguous, i.e.
/// whether some *other* word is also one edit away from it.
public struct Lexicon: Sendable {
    public let words: Set<String>   // lowercased

    public init<S: Sequence>(_ words: S) where S.Element == String {
        self.words = Set(words.map { $0.lowercased() })
    }

    public func contains(_ w: String) -> Bool { words.contains(w.lowercased()) }

    /// Lexicon words exactly one edit from `typo`.
    public func neighbors(of typo: String) -> Set<String> {
        Typos.allEdits(of: typo).intersection(words)
    }

    /// A typo of `word` is unambiguous when `word` is its only lexicon
    /// neighbour. A spell checker that has `word` and is asked about such a
    /// typo has no better candidate to offer.
    public func isUnambiguous(typo: String, for word: String) -> Bool {
        neighbors(of: typo) == [word.lowercased()]
    }
}

public enum Verdict: String, Codable, Sendable {
    /// The checker flags the word itself as misspelled; nothing to measure.
    case rejected
    /// Too short, or not enough genuine typos could be built.
    case untestable
    /// Came back as a guess for at least one typo.
    case suggested
    /// Never came back exactly, but a different form of the same word did
    /// ("Bostons" -> "Boston's"). A ranking quirk, not suppression.
    case related
    /// Never came back, and neither did any other form of it, across a full
    /// battery of genuine typos.
    case suppressed
    /// Never came back, but too few genuine typos could be tested to say so.
    case borderline
}

public struct Trial: Codable, Sendable, Equatable {
    public let typo: String
    public let kind: TypoKind
    public let unambiguous: Bool
    public let hit: Bool
    /// A different form of the word was offered (see `Inflection.related`).
    public let related: Bool
    /// The checker's guesses, best first, truncated to `Trial.keep`.
    public let guesses: [String]
    public var guessCount: Int { guesses.count }

    public static let keep = 8

    public init(typo: String, kind: TypoKind, unambiguous: Bool, hit: Bool, related: Bool = false, guesses: [String]) {
        self.typo = typo
        self.kind = kind
        self.unambiguous = unambiguous
        self.hit = hit
        self.related = related
        self.guesses = Array(guesses.prefix(Self.keep))
    }
}

public struct WordResult: Codable, Sendable {
    public let word: String
    public let verdict: Verdict
    public let trials: [Trial]
    /// Whether the word appears among completions of its own prefix (word
    /// minus its last letter). Only measured when guesses never hit.
    public let completionHit: Bool?
    /// Whether autocorrect turned any typo into the word. Only measured when
    /// guesses never hit.
    public let correctionHit: Bool?

    public var misses: Int { trials.filter { !$0.hit }.count }
    public var unambiguousMisses: Int { trials.filter { !$0.hit && $0.unambiguous }.count }
    public var emptyGuessLists: Int { trials.filter { $0.guessCount == 0 }.count }
    /// Two or more misses on typos whose only lexicon neighbour is the word
    /// itself: the checker had no competing candidate and still said nothing.
    public var hasUnambiguousEvidence: Bool { unambiguousMisses >= 2 }
}

public struct ProbePolicy: Sendable {
    /// Typos in a full battery.
    public var battery: Int = 8
    /// Misses needed (with zero hits) to call a word suppressed.
    public var minMisses: Int = 6
    /// Stop at the first hit. Off for the control sample, which needs the
    /// full battery to measure per-typo recovery rates.
    public var earlyExit: Bool = true
    /// Words shorter than this are untestable: their typos collide with too
    /// many other words to mean anything.
    public var minLength: Int = 4
    /// Typos that must return only a related form before a word is labelled
    /// `.related` rather than flagged.
    public var minRelated: Int = 2
    /// Replace the battery with every keyboard-plausible single edit
    /// (`Typos.neighbourhood`), with no early exit. The verification pass.
    public var fullNeighbourhood: Bool = false

    public init() {}
}

public struct Prober {
    public let oracle: SpellOracle
    public let lexicon: Lexicon
    public let policy: ProbePolicy

    public init(oracle: SpellOracle, lexicon: Lexicon, policy: ProbePolicy = ProbePolicy()) {
        self.oracle = oracle
        self.lexicon = lexicon
        self.policy = policy
    }

    static func matches(_ guess: String, _ word: String) -> Bool {
        // Case-insensitive on purpose: if "Suicide" were offered for "suicde"
        // the word is being suggested, and we must not count that as a miss.
        guess.compare(word, options: .caseInsensitive) == .orderedSame
    }

    /// A guess "stands in" for the word when it is another form of it that
    /// is further from the typo than the word itself: "Bostns" -> "Boston's"
    /// (two edits) instead of "Bostons" (one). That is the checker reaching
    /// for the right family and ranking the wrong member, not suppression.
    /// A related form that is itself one edit from the typo ("suicied" ->
    /// "suicided") is a legitimate competitor and clears nothing.
    static func isRelatedStandIn(_ guess: String, for word: String, typo: String) -> Bool {
        Inflection.related(guess, word) && Typos.osaDistance(guess.lowercased(), typo.lowercased()) > 1
    }

    public func probe(_ word: String) -> WordResult {
        // Internal capitals (BigQuery, NVIDIA) are brand spellings the checker
        // treats specially; their typos say nothing about suppression.
        guard word.count >= policy.minLength, !word.dropFirst().contains(where: \.isUppercase) else {
            return WordResult(word: word, verdict: .untestable, trials: [], completionHit: nil, correctionHit: nil)
        }
        guard oracle.isAccepted(word) else {
            return WordResult(word: word, verdict: .rejected, trials: [], completionHit: nil, correctionHit: nil)
        }

        // Only genuine misspellings count: a typo the checker accepts as a
        // word ("form" -> "from") tells us nothing. The checker is the only
        // judge here; a typo that is in some bigger word list but that the
        // checker rejects ("diety") is exactly the kind of typo to test.
        var trials: [Trial] = []
        var probed: [Typo] = []
        let candidates = policy.fullNeighbourhood
            ? Typos.neighbourhood(of: word)
            : Typos.battery(for: word, limit: policy.battery * 2)
        let limit = policy.fullNeighbourhood ? Int.max : policy.battery
        for typo in candidates {
            if probed.count == limit { break }
            if oracle.isAccepted(typo.text) { continue }
            probed.append(typo)
            let g = oracle.guesses(for: typo.text)
            let hit = g.contains { Self.matches($0, word) }
            trials.append(Trial(
                typo: typo.text,
                kind: typo.kind,
                unambiguous: lexicon.isUnambiguous(typo: typo.text, for: word),
                hit: hit,
                related: !hit && g.contains { Self.isRelatedStandIn($0, for: word, typo: typo.text) },
                guesses: g
            ))
            if hit && policy.earlyExit && !policy.fullNeighbourhood { break }
        }

        if trials.contains(where: { $0.hit }) {
            return WordResult(word: word, verdict: .suggested, trials: trials, completionHit: nil, correctionHit: nil)
        }
        if trials.isEmpty {
            return WordResult(word: word, verdict: .untestable, trials: [], completionHit: nil, correctionHit: nil)
        }
        // One stray related form out of ~90 typos proves little; two or more
        // means the checker keeps reaching for the family.
        if trials.filter(\.related).count >= policy.minRelated {
            return WordResult(word: word, verdict: .related, trials: trials, completionHit: nil, correctionHit: nil)
        }

        let prefix = String(word.dropLast())
        let completionHit = oracle.completions(for: prefix).contains { Self.matches($0, word) }
        let correctionHit = trials.contains { t in
            oracle.correction(for: t.typo).map { Self.matches($0, word) } ?? false
        }

        // Offered through another channel (autocorrect, completion) is still
        // offered: such a word does not belong on a "never suggested" list.
        let offeredElsewhere = completionHit || correctionHit
        return WordResult(
            word: word,
            verdict: offeredElsewhere ? .suggested : (trials.count >= policy.minMisses ? .suppressed : .borderline),
            trials: trials,
            completionHit: completionHit,
            correctionHit: correctionHit
        )
    }
}
