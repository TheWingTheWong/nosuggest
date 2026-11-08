import XCTest
@testable import NoSuggestCore

final class ProberTests: XCTestCase {
    func makeWorld(seed: UInt64, size: Int = 3000, planted: Int = 60) -> (dict: Set<String>, suppressed: Set<String>) {
        let words = randomWords(count: size, seed: seed)
        var rng = Stats.SplitMix64(seed: seed ^ 0xABCD)
        let suppressed = Set(words.shuffled(using: &rng).prefix(planted))
        return (Set(words), suppressed)
    }

    func testRecoversPlantedSetExactlyWithPerfectChecker() {
        let (dict, sup) = makeWorld(seed: 11)
        let oracle = SimulatedChecker(dictionary: dict, suppressed: sup)
        let prober = Prober(oracle: oracle, lexicon: Lexicon(dict))
        var found: Set<String> = []
        for w in dict {
            let r = prober.probe(w)
            XCTAssertNotEqual(r.verdict, .rejected)
            if [.suppressed, .borderline, .related].contains(r.verdict) { found.insert(w) }
            if r.verdict == .suggested { XCTAssertFalse(sup.contains(w), w) }
        }
        XCTAssertEqual(found, sup)
    }

    /// Property: with a lossy checker that drops a fair share of correct
    /// candidates, ordinary words almost never look suppressed, and every
    /// planted word is still found. With 8 typos and a 30% drop rate the
    /// chance of a false positive is 0.3^8, about 7 in 100,000.
    func testLossyCheckerHasNoFalsePositivesAndFullRecall() {
        var falsePositives = 0, ordinary = 0, recalled = 0, planted = 0
        for seed in UInt64(1)...4 {
            let (dict, sup) = makeWorld(seed: seed * 101)
            let oracle = SimulatedChecker(dictionary: dict, suppressed: sup, dropRate: 0.3, salt: seed)
            let prober = Prober(oracle: oracle, lexicon: Lexicon(dict))
            for w in dict {
                let r = prober.probe(w)
                if sup.contains(w) {
                    planted += 1
                    if [.suppressed, .borderline, .related].contains(r.verdict) { recalled += 1 }
                } else if r.verdict != .untestable {
                    ordinary += 1
                    if r.verdict == .suppressed { falsePositives += 1 }
                }
            }
        }
        XCTAssertEqual(recalled, planted)
        XCTAssertGreaterThan(ordinary, 10_000)
        XCTAssertLessThanOrEqual(falsePositives, 2, "\(falsePositives) of \(ordinary)")
    }

    func testRejectsWordsTheCheckerDoesNotKnow() {
        let oracle = SimulatedChecker(dictionary: ["receive"], suppressed: [])
        let r = Prober(oracle: oracle, lexicon: Lexicon(["receive"])).probe("recieve")
        XCTAssertEqual(r.verdict, .rejected)
        XCTAssertTrue(r.trials.isEmpty)
    }

    /// A typo that is itself a real word ("form" -> "from") must not count as
    /// a miss, or common words with many neighbours would look suppressed.
    func testSkipsTyposThatAreRealWords() {
        let dict: Set<String> = ["form", "from", "farm", "firm", "foam"]
        let oracle = SimulatedChecker(dictionary: dict, suppressed: ["form"])
        let r = Prober(oracle: oracle, lexicon: Lexicon(dict)).probe("form")
        for t in r.trials { XCTAssertFalse(dict.contains(t.typo), t.typo) }
    }

    func testCaseInsensitiveMatchCountsAsSuggested() {
        struct Capitalising: SpellOracle {
            func isAccepted(_ w: String) -> Bool { w.lowercased() == "suicide" }
            func guesses(for typo: String) -> [String] { ["Suicide"] }
            func completions(for prefix: String) -> [String] { [] }
            func correction(for typo: String) -> String? { nil }
        }
        let r = Prober(oracle: Capitalising(), lexicon: Lexicon(["suicide"])).probe("suicide")
        XCTAssertEqual(r.verdict, .suggested)
    }

    func testSuppressedWordsRecordCompletionAndCorrectionChannels() {
        let dict: Set<String> = ["contraception", "contraceptive", "conception"]
        let oracle = SimulatedChecker(dictionary: dict, suppressed: ["contraception"])
        var policy = ProbePolicy()
        policy.earlyExit = false
        let r = Prober(oracle: oracle, lexicon: Lexicon(dict), policy: policy).probe("contraception")
        XCTAssertEqual(r.verdict, .suppressed)
        XCTAssertEqual(r.trials.count, 8)
        XCTAssertEqual(r.completionHit, false)
        XCTAssertEqual(r.correctionHit, false)
        XCTAssertTrue(r.hasUnambiguousEvidence)
    }

    func testFullBatteryWhenEarlyExitDisabled() {
        let (dict, _) = makeWorld(seed: 5, size: 300, planted: 0)
        var policy = ProbePolicy()
        policy.earlyExit = false
        let prober = Prober(oracle: SimulatedChecker(dictionary: dict, suppressed: []), lexicon: Lexicon(dict), policy: policy)
        let long = dict.filter { $0.count >= 9 }.sorted().prefix(30)
        for w in long {
            let r = prober.probe(w)
            XCTAssertEqual(r.verdict, .suggested)
            XCTAssertEqual(r.trials.count, 8, w)
        }
    }

    func testRelatedFormIsNotSuppression() {
        struct OffersPossessive: SpellOracle {
            func isAccepted(_ w: String) -> Bool { ["bostons", "boston"].contains(w.lowercased()) }
            func guesses(for typo: String) -> [String] { ["Boston", "Boston's"] }
            func completions(for prefix: String) -> [String] { [] }
            func correction(for typo: String) -> String? { nil }
        }
        let r = Prober(oracle: OffersPossessive(), lexicon: Lexicon(["Bostons", "Boston"])).probe("Bostons")
        XCTAssertEqual(r.verdict, .related)
        XCTAssertTrue(r.trials.allSatisfy(\.related))
    }

    func testInternalCapitalsAreUntestable() {
        let oracle = SimulatedChecker(dictionary: ["bigquery"], suppressed: [])
        XCTAssertEqual(Prober(oracle: oracle, lexicon: Lexicon([])).probe("BigQuery").verdict, .untestable)
    }

    func testUnambiguity() {
        let lex = Lexicon(["suicide", "suite", "suited"])
        XCTAssertTrue(lex.isUnambiguous(typo: "suicde", for: "suicide"))
        XCTAssertFalse(lex.isUnambiguous(typo: "suitd", for: "suite"))    // suite and suited
        XCTAssertTrue(lex.isUnambiguous(typo: "Suicde", for: "Suicide"))
    }
}
