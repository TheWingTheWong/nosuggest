/// Single-edit misspellings, generated deterministically.
///
/// Every typo produced here is exactly one Damerau edit (deletion, adjacent
/// transposition, substitution or insertion) away from the source word. The
/// first letter is never touched: spell checkers lean heavily on it, and
/// people rarely get it wrong, so a first-letter typo is a weak probe.

public enum TypoKind: String, Codable, CaseIterable, Sendable {
    case deletion
    case transposition
    case substitution
    case insertion
}

public struct Typo: Hashable, Codable, Sendable {
    public let text: String
    public let kind: TypoKind
    /// Index (in characters) of the edited position in the source word.
    public let position: Int

    public init(text: String, kind: TypoKind, position: Int) {
        self.text = text
        self.kind = kind
        self.position = position
    }
}

public enum Typos {
    /// Letters adjacent on a US QWERTY keyboard. Substitutions use these so the
    /// probe looks like a real slip of the finger rather than a random letter.
    static let qwertyNeighbors: [Character: [Character]] = {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { Array($0) }
        var map: [Character: [Character]] = [:]
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                var near: [Character] = []
                if c > 0 { near.append(row[c - 1]) }
                if c + 1 < row.count { near.append(row[c + 1]) }
                // Keys in the rows above and below. Rows are staggered by about
                // half a key, so "the same column and one either side" is a
                // slightly generous but simple notion of adjacency.
                for rr in [r - 1, r + 1] where rr >= 0 && rr < rows.count {
                    for cc in (c - 1)...(c + 1) where cc >= 0 && cc < rows[rr].count {
                        near.append(rows[rr][cc])
                    }
                }
                map[ch] = Array(Set(near)).sorted()
            }
        }
        return map
    }()

    /// Interior positions ordered from the middle outwards, so the first typos
    /// in a battery sit where the word is most distinctive.
    static func positionsByCentrality(count n: Int, range: ClosedRange<Int>) -> [Int] {
        guard range.lowerBound <= range.upperBound else { return [] }
        let mid = Double(n - 1) / 2.0
        return Array(range).sorted { a, b in
            let da = abs(Double(a) - mid), db = abs(Double(b) - mid)
            return da == db ? a < b : da < db
        }
    }

    /// All typos of one kind, most central first. Duplicates and the word
    /// itself are removed.
    public static func candidates(of word: String, kind: TypoKind) -> [Typo] {
        let chars = Array(word)
        let n = chars.count
        guard n >= 3 else { return [] }
        var out: [Typo] = []
        var seen: Set<String> = [word]
        func add(_ cs: [Character], _ pos: Int) {
            let s = String(cs)
            if seen.insert(s).inserted { out.append(Typo(text: s, kind: kind, position: pos)) }
        }
        switch kind {
        case .deletion:
            for i in positionsByCentrality(count: n, range: 1...(n - 1)) {
                var cs = chars
                cs.remove(at: i)
                add(cs, i)
            }
        case .transposition:
            // Swap i and i+1, both interior to the first letter.
            for i in positionsByCentrality(count: n - 1, range: 1...(n - 2)) where chars[i] != chars[i + 1] {
                var cs = chars
                cs.swapAt(i, i + 1)
                add(cs, i)
            }
        case .substitution:
            for i in positionsByCentrality(count: n, range: 1...(n - 1)) {
                let original = chars[i]
                let lower = Character(original.lowercased())
                guard let near = qwertyNeighbors[lower] else { continue }
                // One substitution per position keeps the battery spread out.
                if let pick = near.first(where: { $0 != lower }) {
                    var cs = chars
                    cs[i] = pick
                    add(cs, i)
                }
            }
        case .insertion:
            // Doubling a letter is the most common insertion slip.
            for i in positionsByCentrality(count: n, range: 1...(n - 1)) {
                var cs = chars
                cs.insert(chars[i], at: i)
                add(cs, i)
            }
        }
        return out
    }

    /// A battery of up to `limit` typos that cycles through edit kinds, so a
    /// battery of six contains every kind at least once when the word allows.
    public static func battery(for word: String, limit: Int) -> [Typo] {
        let order: [TypoKind] = [.deletion, .transposition, .substitution, .insertion]
        var queues = order.map { candidates(of: word, kind: $0) }
        var out: [Typo] = []
        var seen: Set<String> = []
        var progress = true
        while out.count < limit && progress {
            progress = false
            for k in queues.indices where !queues[k].isEmpty {
                let t = queues[k].removeFirst()
                progress = true
                if seen.insert(t.text).inserted {
                    out.append(t)
                    if out.count == limit { break }
                }
            }
        }
        return out
    }

    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz'-")

    /// Every string within one Damerau edit of `word` (lowercased), over a-z,
    /// apostrophe and hyphen. Used to decide whether a typo is unambiguous.
    public static func allEdits(of word: String) -> Set<String> {
        let cs = Array(word.lowercased())
        let n = cs.count
        var out: Set<String> = []
        for i in 0..<n {
            var d = cs; d.remove(at: i); out.insert(String(d))
            for a in alphabet where a != cs[i] {
                var s = cs; s[i] = a; out.insert(String(s))
            }
        }
        if n >= 2 {
            for i in 0..<(n - 1) where cs[i] != cs[i + 1] {
                var t = cs; t.swapAt(i, i + 1); out.insert(String(t))
            }
        }
        for i in 0...n {
            for a in alphabet {
                var s = cs; s.insert(a, at: i); out.insert(String(s))
            }
        }
        out.remove(String(cs))
        return out
    }

    /// Optimal string alignment distance (Damerau-Levenshtein restricted to
    /// non-overlapping adjacent transpositions).
    public static func osaDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        let n = x.count, m = y.count
        if n == 0 { return m }
        if m == 0 { return n }
        var d = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = i }
        for j in 0...m { d[0][j] = j }
        for i in 1...n {
            for j in 1...m {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[n][m]
    }
}
