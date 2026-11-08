import Foundation
import NoSuggestCore

/// `nosuggest report`: turns a census and its control sample into the JSON
/// the web explorer reads, plus a Markdown summary on stdout.
enum Report {
    struct Word: Codable {
        let w: String          // word
        let v: String          // verdict: "suppressed" or "borderline"
        let size: Int?         // SCOWL size (10 = most common ... 70)
        let cat: String        // editorial category, see data/categories.tsv
        let ios: Bool          // appears inside an iOS keyboard blocklist phrase
        let hunspell: Bool     // NOSUGGEST in the Hunspell en_US dictionary
        let ex: [[String]]     // per typo: [typo, guess1, guess2, ...]
        let empty: Int         // typos that got an empty guess list
        let unamb: Int         // misses on unambiguous typos
        let completion: Bool?  // offered as a completion of its prefix
        let correction: Bool?  // ever produced by autocorrect
    }

    struct Comparison: Codable {
        let iosPhrases: Int
        let iosWords: Int
        let suppressedInIOSPhrase: Int
        let suppressedNotInIOS: Int
        let hunspellNoSuggest: [String: String]   // stem -> macOS verdict
    }

    struct Summary: Codable {
        let os: String
        let language: String
        let generated: String
        let lexiconWords: Int
        let census: CensusSummary
        /// Control for lowercase words and for capitalised words (names,
        /// places, demonyms), which the checker treats differently.
        let control: ControlSummary
        let controlCapitalised: ControlSummary
        let expectedFalsePositives: Double
        let expectedFalsePositivesCapitalised: Double
        let suppressedLowercase: Int
        let suppressedCapitalised: Int
        let bySize: [String: [Int]]               // size -> [tested, suppressed]
        let byCategory: [String: Int]
        let comparison: Comparison
    }

    static func loadResults(_ path: String) -> [WordResult] {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
        let dec = JSONDecoder()
        return s.split(separator: "\n").map { try! dec.decode(WordResult.self, from: Data($0.utf8)) }
    }

    static func loadSizes(_ path: String) -> [String: Int] {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var out: [String: Int] = [:]
        for line in s.split(separator: "\n") {
            let p = line.split(separator: "\t")
            if p.count == 2, let n = Int(p[1]) { out[String(p[0])] = n }
        }
        return out
    }

    /// Ordered (category, regex) rules; the first match wins.
    static func loadCategories(_ path: String) -> [(String, NSRegularExpression)] {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap { line in
            if line.hasPrefix("#") { return nil }
            let p = line.split(separator: "\t", maxSplits: 1)
            guard p.count == 2, let re = try? NSRegularExpression(pattern: "^(?:\(p[1]))$", options: [.caseInsensitive])
            else { return nil }
            return (String(p[0]), re)
        }
    }

    static func category(_ w: String, _ rules: [(String, NSRegularExpression)]) -> String {
        let r = NSRange(location: 0, length: (w as NSString).length)
        if let hit = rules.first(where: { $0.1.firstMatch(in: w, range: r) != nil }) { return hit.0 }
        return (w.first?.isUppercase ?? false) ? "names and places" : "other"
    }

    /// Every word that occurs in any iOS keyboard blocklist phrase or form.
    static func loadIOSWords(_ path: String) -> (phrases: Int, words: Set<String>) {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let rows = j["rows"] as? [[String: Any]] else { return (0, []) }
        var words: Set<String> = []
        for row in rows {
            let phrases = [row["p"] as? String].compactMap { $0 } + ((row["f"] as? [String]) ?? [])
            for p in phrases {
                for t in p.lowercased().split(whereSeparator: { !$0.isLetter }) { words.insert(String(t)) }
            }
        }
        return (rows.count, words)
    }

    /// Stems flagged NOSUGGEST ("!") in a Hunspell .dic file.
    static func loadHunspellNoSuggest(_ path: String) -> [String] {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").dropFirst().compactMap { line in
            let p = line.split(separator: "/", maxSplits: 1)
            guard p.count == 2, p[1].contains("!") else { return nil }
            return String(p[0])
        }
    }

    static func run(_ opts: Options) {
        let dir = opts.string("data", "data/26.5.1")
        let lang = opts.string("language", "en")
        let outDir = opts.string("out", "docs/data")
        let results = loadResults("\(dir)/probe-\(lang).jsonl")
        let control = loadResults("\(dir)/control-\(lang).jsonl")
        let sizes = loadSizes(opts.string("lexicon", "lexicon/en.txt"))
        let rules = loadCategories(opts.string("categories", "data/categories.tsv"))
        let ios = loadIOSWords(opts.string("ios", "work/ios-keyboard-en.json"))
        let hun = loadHunspellNoSuggest(opts.string("hunspell", "work/hunspell-en_US.dic"))
        let hunSet = Set(hun.map { $0.lowercased() })

        let env = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "\(dir)/env.json")))) as? [String: Any]
        let os = env?["os"] as? String ?? "unknown"

        let census = CensusSummary(results: results)
        func isCap(_ w: String) -> Bool { w.first?.isUppercase ?? false }
        let ctl = ControlSummary(results: control.filter { !isCap($0.word) }, batterySize: 8)
        let ctlCap = ControlSummary(results: control.filter { isCap($0.word) }, batterySize: 8)
        // Words that reached the decision point: every non-suggested word that
        // went through a full battery, plus every suggested word (which would
        // have, had it missed).
        let decided = results.filter { [.suppressed, .suggested, .related].contains($0.verdict) }
        let expectedFP = ctl.chanceAllMiss * Double(decided.filter { !isCap($0.word) }.count)
        let expectedFPCap = ctlCap.chanceAllMiss * Double(decided.filter { isCap($0.word) }.count)
        let supAll = results.filter { $0.verdict == .suppressed }

        let flagged = results.filter { $0.verdict == .suppressed || $0.verdict == .borderline }
        let words: [Word] = flagged.map { r in
            Word(w: r.word, v: r.verdict.rawValue, size: sizes[r.word], cat: category(r.word, rules),
                 ios: ios.words.contains(r.word.lowercased()), hunspell: hunSet.contains(r.word.lowercased()),
                 ex: r.trials.map { [$0.typo] + $0.guesses }, empty: r.emptyGuessLists, unamb: r.unambiguousMisses,
                 completion: r.completionHit, correction: r.correctionHit)
        }.sorted { ($0.size ?? 99, $0.w.lowercased()) < ($1.size ?? 99, $1.w.lowercased()) }

        var bySize: [String: [Int]] = [:]
        for r in results where !r.trials.isEmpty {
            let k = String(sizes[r.word] ?? 0)
            var v = bySize[k] ?? [0, 0]
            v[0] += 1
            if r.verdict == .suppressed { v[1] += 1 }
            bySize[k] = v
        }
        var byCat: [String: Int] = [:]
        for w in words where w.v == "suppressed" { byCat[w.cat, default: 0] += 1 }

        let byWord = Dictionary(results.map { ($0.word.lowercased(), $0.verdict.rawValue) }, uniquingKeysWith: { a, _ in a })
        var hunVerdicts: [String: String] = [:]
        for h in hun { hunVerdicts[h] = byWord[h.lowercased()] ?? "not in lexicon" }
        let supWords = words.filter { $0.v == "suppressed" }
        let cmp = Comparison(iosPhrases: ios.phrases, iosWords: ios.words.count,
                             suppressedInIOSPhrase: supWords.filter(\.ios).count,
                             suppressedNotInIOS: supWords.filter { !$0.ios }.count,
                             hunspellNoSuggest: hunVerdicts)

        let iso = ISO8601DateFormatter().string(from: Date())
        let summary = Summary(os: os, language: lang, generated: iso, lexiconWords: results.count,
                              census: census, control: ctl, controlCapitalised: ctlCap,
                              expectedFalsePositives: expectedFP, expectedFalsePositivesCapitalised: expectedFPCap,
                              suppressedLowercase: supAll.filter { !isCap($0.word) }.count,
                              suppressedCapitalised: supAll.filter { isCap($0.word) }.count,
                              bySize: bySize, byCategory: byCat, comparison: cmp)

        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try! enc.encode(words).write(to: URL(fileURLWithPath: "\(outDir)/words-\(lang).json"))
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        try! enc.encode(summary).write(to: URL(fileURLWithPath: "\(outDir)/summary-\(lang).json"))

        // Plain list, one word per line, for anyone who just wants the data.
        try! supWords.map(\.w).sorted().joined(separator: "\n").appending("\n")
            .write(toFile: "\(dir)/suppressed-\(lang).txt", atomically: true, encoding: .utf8)

        printMarkdown(summary, words: words)
    }

    static func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }

    static func printMarkdown(_ s: Summary, words: [Word]) {
        let c = s.census
        print("## Census: \(s.os), language \(s.language)\n")
        print("| | words |")
        print("|---|---:|")
        for k in ["suggested", "related", "suppressed", "borderline", "rejected", "untestable"] {
            print("| \(k) | \(c.counts[k] ?? 0) |")
        }
        print("\nSuppressed words: \(c.suppressed)")
        print("- with >= 2 misses on unambiguous typos: \(c.suppressedWithUnambiguousEvidence)")
        print("- also absent from prefix completions: \(c.suppressedAlsoMissingFromCompletions)")
        print("- never produced by autocorrect: \(c.suppressedNeverAutocorrected)")
        print("- typos answered with an empty guess list: \(pct(c.suppressedEmptyListShare))")
        print("- lowercase: \(s.suppressedLowercase), capitalised: \(s.suppressedCapitalised)")
        for (label, k, fp, sup) in [("lowercase", s.control, s.expectedFalsePositives, s.suppressedLowercase),
                                    ("capitalised", s.controlCapitalised, s.expectedFalsePositivesCapitalised, s.suppressedCapitalised)] {
        print("\n## Control (\(label)): full 8-typo battery on \(k.wordsTested) random words\n")
        print("Hit histogram (0...8): \(k.histogram.map(String.init).joined(separator: " "))")
        for r in k.perKind {
            print("- \(r.kind): \(pct(r.rate)) recovered (95% CI \(pct(r.low))-\(pct(r.high)), n=\(r.trials))")
        }
        print("- unambiguous typos: \(pct(k.unambiguousRate.rate)) (n=\(k.unambiguousRate.trials))")
        print(String(format: "\nFitted chance that an ordinary word misses all 8: %.2e", k.chanceAllMiss))
        print(String(format: "Expected chance false positives: %.1f of %d suppressed", fp, sup))
        print("Control words with 0/8: \(k.controlZeros.joined(separator: ", "))")
        }
        print("\n## Categories (suppressed)\n")
        for (cat, n) in s.byCategory.sorted(by: { $0.value > $1.value }) { print("- \(cat): \(n)") }
        let cmp = s.comparison
        print("\n## Comparison\n")
        print("iOS keyboard list: \(cmp.iosPhrases) phrases, \(cmp.iosWords) distinct words inside them")
        print("Suppressed words that occur in some iOS phrase: \(cmp.suppressedInIOSPhrase); not in any: \(cmp.suppressedNotInIOS)")
        print("Hunspell NOSUGGEST stems and their macOS verdicts:")
        for (w, v) in cmp.hunspellNoSuggest.sorted(by: { $0.key < $1.key }) { print("  \(w): \(v)") }
    }
}
