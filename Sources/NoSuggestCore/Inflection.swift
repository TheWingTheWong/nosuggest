/// Are two words inflections of the same English word?
///
/// The checker sometimes answers a typo of an inflected form with a different
/// form of the same word ("Bostns" -> "Boston's"). That is a ranking quirk,
/// not suppression. The test here is deliberately narrow: only plural and
/// possessive endings and the regular verb endings count, with English's
/// actual spelling rules for them. Derivational suffixes (-er, -ism, -ist,
/// -ly, -ness) never do, and neither does undoing a doubled consonant, because
/// those make unrelated words look related ("raped"/"rapped" -> "rap",
/// "retarded"/"retarder", "terrorism"/"terror's").
public enum Inflection {
    static let sibilantEndings = ["s", "x", "z", "ch", "sh"]

    /// The word itself plus the bases it can be an inflection of.
    public static func bases(_ word: String) -> Set<String> {
        let w = word.lowercased()
        var out: Set<String> = [w]
        func add(_ b: String) { if b.count >= 3 { out.insert(b) } }
        // Possessives.
        if w.hasSuffix("'s") { add(String(w.dropLast(2))) }
        if w.hasSuffix("s'") { add(String(w.dropLast(2))) }
        // Plurals and third person: -s always; -es only after a sibilant;
        // -ies from -y.
        if w.hasSuffix("s"), !w.hasSuffix("ss"), !w.hasSuffix("'s") { add(String(w.dropLast())) }
        if w.hasSuffix("es") {
            let stem = String(w.dropLast(2))
            if sibilantEndings.contains(where: stem.hasSuffix) { add(stem) }
        }
        if w.hasSuffix("ies") { add(String(w.dropLast(3)) + "y") }
        // Past tense and participles: -ed, -d after e, -ied from -y, -ing
        // with or without a dropped e.
        if w.hasSuffix("ied") { add(String(w.dropLast(3)) + "y") }
        if w.hasSuffix("ed") { add(String(w.dropLast(2))) }
        if w.hasSuffix("ed") { add(String(w.dropLast(1))) }      // "bared" -> "bare"
        if w.hasSuffix("ing") {
            add(String(w.dropLast(3)))
            add(String(w.dropLast(3)) + "e")
        }
        return out
    }

    /// True when `a` and `b` differ (ignoring case) and one is an inflection
    /// of the other, or both are inflections of a common base.
    public static func related(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased(), y = b.lowercased()
        guard x != y else { return false }
        return !bases(x).isDisjoint(with: bases(y))
    }
}
