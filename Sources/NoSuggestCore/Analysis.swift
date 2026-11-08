import Foundation

/// How often does an ordinary word fail to come back from all of its typos by
/// chance? The control sample answers this without assuming anything about
/// which words are "sensitive":
///
/// 1. Take the hit counts (out of n typos) of control words that came back at
///    least once. Those words are certainly not suppressed.
/// 2. Fit a beta-binomial to that zero-truncated histogram. The beta part
///    absorbs the fact that some words are harder to recover than others.
/// 3. The fitted P(0 hits) is the chance that an ordinary word looks
///    suppressed. Multiply by the number of words tested to get the expected
///    number of false positives in the census.
///
/// The extrapolation to zero is a model, so the histogram itself is reported
/// too: if chance zeros were common, one-hit words would be common as well.
public struct BetaBinomial: Equatable, Sendable {
    public let n: Int
    public let alpha: Double
    public let beta: Double

    public init(n: Int, alpha: Double, beta: Double) {
        self.n = n
        self.alpha = alpha
        self.beta = beta
    }

    static func logBeta(_ a: Double, _ b: Double) -> Double { lgamma(a) + lgamma(b) - lgamma(a + b) }
    static func logChoose(_ n: Int, _ k: Int) -> Double {
        lgamma(Double(n + 1)) - lgamma(Double(k + 1)) - lgamma(Double(n - k + 1))
    }

    public func logPMF(_ k: Int) -> Double {
        Self.logChoose(n, k) + Self.logBeta(Double(k) + alpha, Double(n - k) + beta) - Self.logBeta(alpha, beta)
    }

    public func pmf(_ k: Int) -> Double { exp(logPMF(k)) }

    /// Log-likelihood of a histogram (index = hit count) with the zero bin
    /// excluded and the rest renormalised.
    public func zeroTruncatedLogLikelihood(_ histogram: [Int]) -> Double {
        let logNotZero = log1p(-pmf(0))
        var ll = 0.0
        for k in 1...n where k < histogram.count && histogram[k] > 0 {
            ll += Double(histogram[k]) * (logPMF(k) - logNotZero)
        }
        return ll
    }

    /// Maximum-likelihood fit to a zero-truncated histogram, by a coarse
    /// log-spaced grid followed by coordinate refinement. Two parameters and
    /// a smooth surface make this reliable without an optimisation library.
    public static func fitZeroTruncated(_ histogram: [Int], n: Int) -> BetaBinomial {
        var best = BetaBinomial(n: n, alpha: 1, beta: 1)
        var bestLL = -Double.infinity
        let grid = stride(from: -3.0, through: 4.0, by: 0.25).map { pow(10, $0 / 2) }
        for a in grid {
            for b in grid {
                let m = BetaBinomial(n: n, alpha: a, beta: b)
                let ll = m.zeroTruncatedLogLikelihood(histogram)
                if ll > bestLL { bestLL = ll; best = m }
            }
        }
        var step = 0.5
        for _ in 0..<60 {
            var improved = false
            for (da, db) in [(step, 0.0), (-step, 0.0), (0.0, step), (0.0, -step)] {
                let a = best.alpha * exp(da), b = best.beta * exp(db)
                let m = BetaBinomial(n: n, alpha: a, beta: b)
                let ll = m.zeroTruncatedLogLikelihood(histogram)
                if ll > bestLL + 1e-12 { bestLL = ll; best = m; improved = true }
            }
            if !improved { step /= 2 }
            if step < 1e-6 { break }
        }
        return best
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
    public let fitAlpha: Double
    public let fitBeta: Double
    /// Fitted probability that a word which is *not* suppressed misses on
    /// every typo of a full battery.
    public let chanceAllMiss: Double
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

        let fit = BetaBinomial.fitZeroTruncated(hist, n: batterySize)
        fitAlpha = fit.alpha
        fitBeta = fit.beta
        chanceAllMiss = fit.pmf(0)
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
