import Foundation
@testable import NoSuggestCore

/// A spell checker with known ground truth, for testing the prober.
///
/// It accepts every word in `dictionary`. For a typo it offers every
/// dictionary word one edit away, except words in `suppressed`, and drops
/// each legitimate candidate with probability `dropRate` (decided by a hash of
/// typo and word, so runs are reproducible). Real checkers miss candidates for
/// many reasons, such as ranking cut-offs and frequency, and the drop rate
/// stands in for all of them.
struct SimulatedChecker: SpellOracle {
    let dictionary: Set<String>
    let suppressed: Set<String>
    var dropRate: Double = 0
    var maxGuesses: Int = 12
    var salt: UInt64 = 0

    func isAccepted(_ word: String) -> Bool { dictionary.contains(word.lowercased()) }

    private func dropped(_ typo: String, _ word: String) -> Bool {
        guard dropRate > 0 else { return false }
        var h: UInt64 = 1469598103934665603 ^ salt
        for b in (typo + "\u{1}" + word).utf8 {
            h = (h ^ UInt64(b)) &* 1099511628211
        }
        var rng = Stats.SplitMix64(seed: h)
        return Double(rng.next() >> 11) / Double(1 << 53) < dropRate
    }

    func guesses(for typo: String) -> [String] {
        let near = Typos.allEdits(of: typo).intersection(dictionary)
        return near.subtracting(suppressed).filter { !dropped(typo, $0) }.sorted().prefix(maxGuesses).map { $0 }
    }

    func completions(for prefix: String) -> [String] {
        dictionary.filter { $0.hasPrefix(prefix.lowercased()) && !suppressed.contains($0) }.sorted()
    }

    func correction(for typo: String) -> String? {
        let g = guesses(for: typo)
        return g.count == 1 ? g[0] : nil
    }
}

/// Random lowercase words with a realistic-ish letter mix.
func randomWords(count: Int, seed: UInt64, lengths: ClosedRange<Int> = 4...11) -> [String] {
    var rng = Stats.SplitMix64(seed: seed)
    let letters = Array("eeeeeaaaaiiiioooonnnrrrsssttllcdumhgpbfywkvxzjq")
    var out: Set<String> = []
    while out.count < count {
        let n = Int.random(in: lengths, using: &rng)
        out.insert(String((0..<n).map { _ in letters.randomElement(using: &rng)! }))
    }
    return out.sorted()
}
