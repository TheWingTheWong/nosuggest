import Foundation

/// Hand labels for a sample of words, read from a TSV of
/// `word<TAB>label<TAB>note` lines. Labels are "topical", "lookalike" and
/// "none"; see data/<version>/audit-*.tsv for what each means.
public struct Audit: Codable, Sendable {
    public let size: Int
    public let topical: Int
    public let lookalike: Int
    public let none: Int
    /// Share of sampled words with no apparent reason, with a 95% Wilson interval.
    public let noneRate: Double
    public let noneLow: Double
    public let noneHigh: Double
    public let noneWords: [String]
    public let lookalikeWords: [String]

    public init(tsv: String) {
        var t = 0, l = 0, n = 0
        var noneWords: [String] = [], lookWords: [String] = []
        for line in tsv.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 2 else { continue }
            switch f[1] {
            case "topical": t += 1
            case "lookalike": l += 1; lookWords.append(f[0])
            case "none": n += 1; noneWords.append(f[0])
            default: continue
            }
        }
        size = t + l + n
        topical = t
        lookalike = l
        none = n
        let ci = Stats.wilson(successes: n, trials: size)
        noneRate = size == 0 ? 0 : Double(n) / Double(size)
        noneLow = ci.low
        noneHigh = ci.high
        self.noneWords = noneWords
        lookalikeWords = lookWords
    }
}

public struct ControlSummary: Codable, Sendable {
    public struct KindRate: Codable, Sendable {
        public let kind: String
        public let hits: Int
        public let trials: Int
        public let rate: Double
        public let low: Double
        public let high: Double
    }

    /// Battery size the analysis is restricted to (words with a full battery).
    public let batterySize: Int
    public let wordsTested: Int
    /// histogram[k] = control words with exactly k hits out of `batterySize`.
    public let histogram: [Int]
    /// Per-typo recovery rate by edit kind, over control words that came back
    /// at least once.
    public let perKind: [KindRate]
    /// Same, restricted to unambiguous typos.
    public let unambiguousRate: KindRate
    /// Share of all typos, of all control words (including those that never
    /// came back), that brought the word back.
    public let overallRate: Double
    /// Control words judged suppressed (zero hits, no related form offered).
    public let controlZeros: [String]
    /// Control words with zero exact hits where a related form was offered.
    public let controlRelated: Int

    public init(results: [WordResult], batterySize: Int) {
        let full = results.filter { [.suggested, .related, .suppressed].contains($0.verdict) && $0.trials.count == batterySize }
        self.batterySize = batterySize
        wordsTested = full.count
        var hist = Array(repeating: 0, count: batterySize + 1)
        for r in full { hist[r.trials.filter(\.hit).count] += 1 }
        histogram = hist
        controlZeros = full.filter { $0.verdict == .suppressed }.map(\.word).sorted()
        controlRelated = full.filter { $0.verdict == .related }.count

        let recovered = full.filter { $0.trials.contains(where: \.hit) }
        func rate(_ label: String, _ ts: [Trial]) -> KindRate {
            let h = ts.filter(\.hit).count
            let ci = Stats.wilson(successes: h, trials: ts.count)
            return KindRate(kind: label, hits: h, trials: ts.count,
                            rate: ts.isEmpty ? 0 : Double(h) / Double(ts.count), low: ci.low, high: ci.high)
        }
        let allTrials = recovered.flatMap(\.trials)
        perKind = TypoKind.allCases.map { k in rate(k.rawValue, allTrials.filter { $0.kind == k }) }
        unambiguousRate = rate("unambiguous", allTrials.filter(\.unambiguous))
        let every = full.flatMap(\.trials)
        overallRate = every.isEmpty ? 0 : Double(every.filter(\.hit).count) / Double(every.count)
    }
}

public struct CensusSummary: Codable, Sendable {
    public let counts: [String: Int]
    /// Words that went through at least one genuine typo.
    public let tested: Int
    public let suppressed: Int
    public let suppressedWithUnambiguousEvidence: Int
    public let suppressedAlsoMissingFromCompletions: Int
    public let suppressedNeverAutocorrected: Int
    /// Share of suppressed-word typos that got an empty guess list, versus
    /// typos of control words.
    public let suppressedEmptyListShare: Double

    public init(results: [WordResult]) {
        var c: [String: Int] = [:]
        for r in results { c[r.verdict.rawValue, default: 0] += 1 }
        counts = c
        tested = results.filter { !$0.trials.isEmpty }.count
        let sup = results.filter { $0.verdict == .suppressed }
        suppressed = sup.count
        suppressedWithUnambiguousEvidence = sup.filter(\.hasUnambiguousEvidence).count
        suppressedAlsoMissingFromCompletions = sup.filter { $0.completionHit == false }.count
        suppressedNeverAutocorrected = sup.filter { $0.correctionHit == false }.count
        let ts = sup.flatMap(\.trials)
        suppressedEmptyListShare = ts.isEmpty ? 0 : Double(ts.filter { $0.guessCount == 0 }.count) / Double(ts.count)
    }
}
