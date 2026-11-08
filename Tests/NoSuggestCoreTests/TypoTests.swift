import XCTest
@testable import NoSuggestCore

final class TypoTests: XCTestCase {
    func testOSADistanceKnownValues() {
        XCTAssertEqual(Typos.osaDistance("", ""), 0)
        XCTAssertEqual(Typos.osaDistance("abc", ""), 3)
        XCTAssertEqual(Typos.osaDistance("kitten", "sitting"), 3)
        XCTAssertEqual(Typos.osaDistance("suicide", "suicde"), 1)
        XCTAssertEqual(Typos.osaDistance("abortion", "abrotion"), 1)   // one transposition
        XCTAssertEqual(Typos.osaDistance("ca", "abc"), 3)              // OSA, not full Damerau
    }

    func testOSADistanceIsSymmetric() {
        let words = randomWords(count: 200, seed: 7, lengths: 1...7)
        for (a, b) in zip(words, words.reversed()) {
            XCTAssertEqual(Typos.osaDistance(a, b), Typos.osaDistance(b, a))
        }
    }

    /// Property: every typo in every battery is a single edit of the source,
    /// keeps the first letter, is not the source itself, and is unique.
    func testBatteryTyposAreSingleInteriorEdits() {
        for w in randomWords(count: 1500, seed: 1) + ["suicide", "abortion", "Hitler", "mississippi", "aaaa"] {
            let battery = Typos.battery(for: w, limit: 8)
            XCTAssertEqual(Set(battery.map(\.text)).count, battery.count, "duplicates for \(w)")
            for t in battery {
                XCTAssertEqual(Typos.osaDistance(t.text, w), 1, "\(t.text) vs \(w)")
                XCTAssertEqual(t.text.first, w.first, "first letter changed: \(t.text) vs \(w)")
                XCTAssertNotEqual(t.text, w)
            }
        }
    }

    func testBatteryIsDeterministicAndCyclesKinds() {
        let a = Typos.battery(for: "contraception", limit: 8)
        let b = Typos.battery(for: "contraception", limit: 8)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 8)
        XCTAssertEqual(Array(a.prefix(4).map(\.kind)), [.deletion, .transposition, .substitution, .insertion])
        XCTAssertEqual(Set(a.map(\.kind)).count, 4)
    }

    func testBatteryForTooShortWordIsEmpty() {
        XCTAssertTrue(Typos.battery(for: "ab", limit: 8).isEmpty)
    }

    /// Property: allEdits contains exactly strings at distance one. Checked
    /// in both directions: every member is at distance 1, and random single
    /// edits are always members.
    func testAllEditsMatchesDistanceOne() {
        var rng = Stats.SplitMix64(seed: 99)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        for w in randomWords(count: 150, seed: 3, lengths: 2...8) {
            let edits = Typos.allEdits(of: w)
            XCTAssertFalse(edits.contains(w))
            for e in edits.shuffled(using: &rng).prefix(40) {
                XCTAssertEqual(Typos.osaDistance(e, w), 1, "\(e) in allEdits(\(w))")
            }
            var cs = Array(w)
            let i = Int.random(in: 0..<cs.count, using: &rng)
            switch Int.random(in: 0..<4, using: &rng) {
            case 0: cs.remove(at: i)
            case 1: cs[i] = alphabet.randomElement(using: &rng)!
            case 2: cs.insert(alphabet.randomElement(using: &rng)!, at: i)
            default: if i + 1 < cs.count { cs.swapAt(i, i + 1) }
            }
            let t = String(cs)
            if t != w { XCTAssertTrue(edits.contains(t), "\(t) missing from allEdits(\(w))") }
        }
    }

    func testQwertyNeighboursAreSymmetric() {
        for (k, vs) in Typos.qwertyNeighbors {
            XCTAssertFalse(vs.contains(k))
            for v in vs { XCTAssertTrue(Typos.qwertyNeighbors[v]!.contains(k), "\(k)-\(v)") }
        }
        XCTAssertEqual(Typos.qwertyNeighbors.count, 26)
    }
}
