import XCTest
@testable import NoSuggestCore

final class InflectionTests: XCTestCase {
    func testRelatedForms() {
        for (a, b) in [("Bostons", "Boston's"), ("actins", "actin's"), ("bared", "bare"), ("marks", "Mark"),
                       ("abuses", "abuse"), ("parties", "party"), ("hoping", "hope"), ("boxes", "box"),
                       ("suicided", "suicide"), ("churches", "church's")] {
            XCTAssertTrue(Inflection.related(a, b), "\(a) ~ \(b)")
            XCTAssertTrue(Inflection.related(b, a), "\(b) ~ \(a)")
        }
    }

    /// The guesses the checker actually returned for typos of suppressed
    /// words must not be mistaken for forms of those words.
    func testUnrelatedLookalikes() {
        for (a, b) in [("suicide", "suite"), ("suicide", "suited"), ("Hitler", "Hitter"), ("condom", "condo"),
                       ("penis", "pens"), ("murder", "murre"), ("abortion", "abortive"), ("rape", "rap"),
                       ("Nazi", "Nahi"), ("cocaine", "cosine")] {
            XCTAssertFalse(Inflection.related(a, b), "\(a) !~ \(b)")
        }
        XCTAssertFalse(Inflection.related("same", "Same"))
    }

    /// Pairs the real checker produced that a looser stemmer (consonant
    /// undoubling, derivational suffixes, -es after any letter) wrongly
    /// called related, clearing suppressed words.
    func testFalseFamiliesFromRealData() {
        for (a, b) in [("raped", "rapped"), ("rapist", "rap's"), ("sadism", "saddest"), ("pissed", "PIs"),
                       ("molest", "moles"), ("tits", "titter"), ("slaves", "Slavs"), ("spics", "spices"),
                       ("retarded", "retarder"), ("executioner", "execution's"), ("terrorism", "terror's"),
                       ("barer", "bare"), ("quickly", "quick")] {
            XCTAssertFalse(Inflection.related(a, b), "\(a) !~ \(b)")
        }
    }
}
