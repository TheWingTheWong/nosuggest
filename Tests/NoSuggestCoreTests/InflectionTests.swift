import XCTest
@testable import NoSuggestCore

final class InflectionTests: XCTestCase {
    func testRelatedForms() {
        for (a, b) in [("Bostons", "Boston's"), ("actins", "actin's"), ("bared", "bare"), ("barer", "bare"),
                       ("barred", "bar"), ("marks", "Mark"), ("abuses", "abuse"), ("parties", "party"),
                       ("hoping", "hope"), ("quickly", "quick")] {
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
}
