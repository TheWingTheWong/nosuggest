/// Are two words forms of the same English word?
///
/// The checker often answers a typo of an inflected form with a different
/// form of the same word ("Bostns" -> "Boston, Boston's"). That is a ranking
/// quirk, not suppression, and the census must not count it as a miss. This
/// is a deliberately small, conservative suffix stripper. It only needs to
/// recognise when two strings share a stem, not to produce linguistically
/// correct lemmas.
public enum Inflection {
    static let suffixes: [(strip: String, add: String)] = [
        ("'s", ""), ("s'", ""), ("'", ""),
        ("ies", "y"), ("ied", "y"), ("ier", "y"), ("iest", "y"), ("ily", "y"),
        ("es", ""), ("s", ""),
        ("ed", ""), ("d", ""),
        ("ing", ""), ("ing", "e"),
        ("er", ""), ("r", ""), ("est", ""), ("st", ""),
        ("ly", ""), ("ness", ""), ("ism", ""), ("ist", ""),
    ]

    /// The word itself plus every stem reachable by stripping one suffix,
    /// keeping stems of at least three letters.
    public static func stems(_ word: String) -> Set<String> {
        let w = word.lowercased()
        var out: Set<String> = [w]
        for (strip, add) in suffixes where w.hasSuffix(strip) {
            let base = String(w.dropLast(strip.count)) + add
            if base.count >= 3 { out.insert(base) }
            // Undo consonant doubling: "barred" -> "barr" -> "bar".
            if let last = base.last, base.count >= 4, base.dropLast().last == last {
                out.insert(String(base.dropLast()))
            }
        }
        return out
    }

    /// True when `a` and `b` differ (ignoring case) but share a stem.
    public static func related(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased(), y = b.lowercased()
        guard x != y else { return false }
        return !stems(x).isDisjoint(with: stems(y))
    }
}
