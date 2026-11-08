import XCTest
@testable import NoSuggestCore

final class AnalysisTests: XCTestCase {
    func testWilsonKnownValues() {
        let a = Stats.wilson(successes: 0, trials: 10)
        XCTAssertEqual(a.low, 0, accuracy: 1e-12)
        XCTAssertEqual(a.high, 0.2775, accuracy: 1e-4)
        let b = Stats.wilson(successes: 50, trials: 100)
        XCTAssertEqual(b.low, 0.4038, accuracy: 1e-4)
        XCTAssertEqual(b.high, 0.5962, accuracy: 1e-4)
        let c = Stats.wilson(successes: 10, trials: 10)
        XCTAssertEqual(c.high, 1, accuracy: 1e-12)
    }

    func testBetaBinomialPMFSumsToOne() {
        for (a, b) in [(0.5, 0.5), (2.0, 7.0), (30.0, 1.5)] {
            let m = BetaBinomial(n: 8, alpha: a, beta: b)
            let s = (0...8).map(m.pmf).reduce(0, +)
            XCTAssertEqual(s, 1, accuracy: 1e-9)
        }
        // alpha = beta = 1 is uniform over 0...n.
        XCTAssertEqual(BetaBinomial(n: 8, alpha: 1, beta: 1).pmf(3), 1.0 / 9, accuracy: 1e-12)
    }

    /// Property: fitting the zero-truncated histogram of a known beta-binomial
    /// recovers its P(0), which is the quantity the census depends on.
    func testZeroTruncatedFitRecoversHiddenZeroMass() {
        for (a, b) in [(6.0, 1.2), (3.0, 0.8), (12.0, 2.0)] {
            let truth = BetaBinomial(n: 8, alpha: a, beta: b)
            // Expected histogram for 200,000 words, zero bin removed.
            var hist = (0...8).map { Int((truth.pmf($0) * 200_000).rounded()) }
            hist[0] = 0
            let fit = BetaBinomial.fitZeroTruncated(hist, n: 8)
            XCTAssertEqual(fit.pmf(0), truth.pmf(0), accuracy: max(1e-5, truth.pmf(0) * 0.05), "a=\(a) b=\(b)")
        }
    }

    func testControlSummaryOnSimulatedChecker() {
        let words = randomWords(count: 1500, seed: 42, lengths: 8...12)
        let dict = Set(words)
        let sup: Set<String> = Set(words.prefix(15))
        var policy = ProbePolicy()
        policy.earlyExit = false
        let prober = Prober(oracle: SimulatedChecker(dictionary: dict, suppressed: sup, dropRate: 0.25),
                            lexicon: Lexicon(dict), policy: policy)
        let results = words.map(prober.probe)
        let s = ControlSummary(results: results, batterySize: 8)
        XCTAssertEqual(Set(s.controlZeros), sup.intersection(s.controlZeros))  // zeros are planted words
        XCTAssertTrue(sup.isSubset(of: Set(s.controlZeros)))
        XCTAssertEqual(s.histogram.reduce(0, +), s.wordsTested)
        // A 25% independent drop rate means per-typo recovery near 75%.
        let overall = s.perKind.map(\.hits).reduce(0, +)
        let trials = s.perKind.map(\.trials).reduce(0, +)
        XCTAssertEqual(Double(overall) / Double(trials), 0.75, accuracy: 0.03)
        XCTAssertLessThan(s.chanceAllMiss, 1e-3)
    }

    func testCensusSummaryCounts() {
        let t = Trial(typo: "x", kind: .deletion, unambiguous: true, hit: false, guessCount: 0)
        let results = [
            WordResult(word: "a", verdict: .suppressed, trials: Array(repeating: t, count: 8), completionHit: false, correctionHit: false),
            WordResult(word: "b", verdict: .suggested, trials: [Trial(typo: "y", kind: .deletion, unambiguous: false, hit: true, guessCount: 3)], completionHit: nil, correctionHit: nil),
            WordResult(word: "c", verdict: .rejected, trials: [], completionHit: nil, correctionHit: nil),
        ]
        let s = CensusSummary(results: results)
        XCTAssertEqual(s.tested, 2)
        XCTAssertEqual(s.suppressed, 1)
        XCTAssertEqual(s.suppressedWithUnambiguousEvidence, 1)
        XCTAssertEqual(s.suppressedAlsoMissingFromCompletions, 1)
        XCTAssertEqual(s.suppressedEmptyListShare, 1)
        XCTAssertEqual(s.counts["rejected"], 1)
    }
}
