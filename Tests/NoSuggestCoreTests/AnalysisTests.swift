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

    func testAuditCountsAndInterval() {
        let tsv = """
        # comment
        rape\ttopical\t
        rapeseed\tlookalike\tstarts with "rape"
        moshes\tnone\t
        murder\ttopical\t
        bogus\tunknown-label\t
        """
        let a = Audit(tsv: tsv)
        XCTAssertEqual(a.size, 4)
        XCTAssertEqual(a.topical, 2)
        XCTAssertEqual(a.lookalikeWords, ["rapeseed"])
        XCTAssertEqual(a.noneWords, ["moshes"])
        XCTAssertEqual(a.noneRate, 0.25, accuracy: 1e-12)
        XCTAssertLessThan(a.noneLow, 0.25)
        XCTAssertGreaterThan(a.noneHigh, 0.25)
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
    }

    func testCensusSummaryCounts() {
        let t = Trial(typo: "x", kind: .deletion, unambiguous: true, hit: false, guesses: [])
        let results = [
            WordResult(word: "a", verdict: .suppressed, trials: Array(repeating: t, count: 8), completionHit: false, correctionHit: false),
            WordResult(word: "b", verdict: .suggested, trials: [Trial(typo: "y", kind: .deletion, unambiguous: false, hit: true, guesses: ["b", "c", "d"])], completionHit: nil, correctionHit: nil),
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
