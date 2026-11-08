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
        let n: Int             // typos tested in the verification pass
        let ex: [[String]]     // first typos: [typo, guess1, guess2, ...]
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
        // Decoded again by `check-readme`.
        let os: String
        let language: String
        let generated: String
        let lexiconWords: Int
        /// Stage 1: every lexicon word, eight typos each.
        let census: CensusSummary
        /// Stage 2: the words stage 1 flagged, every keyboard-plausible typo.
        /// Its `suppressed` count is the published list.
        let final: CensusSummary
        let verifyTypos: Int
        /// Typos tried in stage 1.
        let probeTypos: Int
        /// Words stage 1 flagged that stage 2 cleared: [word, typo that brought it back].
        let cleared: [[String]]
        /// Control for lowercase words and for capitalised words (names,
        /// places, demonyms), which the checker treats differently.
        let control: ControlSummary
        let controlCapitalised: ControlSummary
        /// Hand-labelled audits: every control word that missed all eight,
        /// and a random sample of the suppressed list.
        let auditControlZeros: Audit?
        let auditSample: Audit?
        let auditBaseRate: Audit?
        /// Words that reached a decision (suggested, related or suppressed).
        let decided: Int
        let suppressedLowercase: Int
        let suppressedCapitalised: Int
        let bySize: [String: [Int]]               // size -> [tested, suppressed]
        let byCategory: [String: Int]
        let comparison: Comparison
    }

    /// Reads a JSONL file, or its committed `.gz` twin when the raw file
    /// isn't there (a fresh clone only has the compressed copies).
    static func loadResults(_ path: String) -> [WordResult] {
        var text = try? String(contentsOfFile: path, encoding: .utf8)
        if text == nil, FileManager.default.fileExists(atPath: path + ".gz") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
            p.arguments = ["-c", path + ".gz"]
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            text = String(decoding: data, as: UTF8.self)
        }
        guard let s = text else { fail("cannot read \(path) or \(path).gz") }
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
        // "entries" counts every phrase including inflected forms, which is
        // the figure Swipeblocked and the press quote.
        return ((j["entries"] as? Int) ?? rows.count, words)
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
        let verify = loadResults("\(dir)/verify-\(lang).jsonl")
        let finalVerdict = Dictionary(verify.map { ($0.word, $0.verdict) }, uniquingKeysWith: { a, _ in a })
        let control = loadResults("\(dir)/control-\(lang).jsonl")
        let sizes = loadSizes(opts.string("lexicon", "lexicon/en.txt"))
        let rules = loadCategories(opts.string("categories", "data/categories.tsv"))
        let ios = loadIOSWords(opts.string("ios", "work/ios-keyboard-en.json"))
        let hun = loadHunspellNoSuggest(opts.string("hunspell", "work/hunspell-en_US.dic"))
        let hunSet = Set(hun.map { $0.lowercased() })

        let env = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "\(dir)/env.json")))) as? [String: Any]
        let os = env?["os"] as? String ?? "unknown"

        let census = CensusSummary(results: results)
        let final = CensusSummary(results: verify)
        let cleared: [[String]] = verify.filter { $0.verdict != .suppressed }.map { r in
            [r.word, r.trials.first(where: \.hit)?.typo ?? r.trials.first(where: \.related)?.typo ?? ""]
        }.sorted { $0[0].lowercased() < $1[0].lowercased() }
        func isCap(_ w: String) -> Bool { w.first?.isUppercase ?? false }
        let ctl = ControlSummary(results: control.filter { !isCap($0.word) }, batterySize: 8)
        let ctlCap = ControlSummary(results: control.filter { isCap($0.word) }, batterySize: 8)
        let decided = results.filter { [.suppressed, .suggested, .related].contains($0.verdict) }.count
        func audit(_ name: String) -> Audit? {
            (try? String(contentsOfFile: "\(dir)/audit-\(name)-\(lang).tsv", encoding: .utf8)).map(Audit.init(tsv:))
        }
        let supAll = verify.filter { $0.verdict == .suppressed }

        let words: [Word] = supAll.map { r in
            Word(w: r.word, v: r.verdict.rawValue, size: sizes[r.word], cat: category(r.word, rules),
                 ios: ios.words.contains(r.word.lowercased()), hunspell: hunSet.contains(r.word.lowercased()),
                 n: r.trials.count, ex: r.trials.prefix(6).map { [$0.typo] + $0.guesses }, empty: r.emptyGuessLists,
                 unamb: r.unambiguousMisses, completion: r.completionHit, correction: r.correctionHit)
        }.sorted { ($0.size ?? 99, $0.w.lowercased()) < ($1.size ?? 99, $1.w.lowercased()) }

        var bySize: [String: [Int]] = [:]
        for r in results where !r.trials.isEmpty {
            let k = String(sizes[r.word] ?? 0)
            var v = bySize[k] ?? [0, 0]
            v[0] += 1
            if finalVerdict[r.word] == .suppressed { v[1] += 1 }
            bySize[k] = v
        }
        var byCat: [String: Int] = [:]
        for w in words where w.v == "suppressed" { byCat[w.cat, default: 0] += 1 }

        let byWord = Dictionary(results.map { ($0.word.lowercased(), (finalVerdict[$0.word] ?? $0.verdict).rawValue) },
                                uniquingKeysWith: { a, _ in a })
        var hunVerdicts: [String: String] = [:]
        for h in hun { hunVerdicts[h] = byWord[h.lowercased()] ?? "not in lexicon" }
        let supWords = words.filter { $0.v == "suppressed" }
        let cmp = Comparison(iosPhrases: ios.phrases, iosWords: ios.words.count,
                             suppressedInIOSPhrase: supWords.filter(\.ios).count,
                             suppressedNotInIOS: supWords.filter { !$0.ios }.count,
                             hunspellNoSuggest: hunVerdicts)

        let iso = ISO8601DateFormatter().string(from: Date())
        let summary = Summary(os: os, language: lang, generated: iso, lexiconWords: results.count,
                              census: census, final: final, verifyTypos: verify.reduce(0) { $0 + $1.trials.count },
                              probeTypos: results.reduce(0) { $0 + $1.trials.count },
                              cleared: cleared, control: ctl, controlCapitalised: ctlCap,
                              auditControlZeros: audit("control-zeros"), auditSample: audit("sample"), auditBaseRate: audit("base-rate"), decided: decided,
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
        let c = s.census, f = s.final
        print("## Census: \(s.os), language \(s.language)\n")
        print("Stage 1, eight typos per word:\n")
        print("| | words |")
        print("|---|---:|")
        for k in ["suggested", "related", "suppressed", "borderline", "rejected", "untestable"] {
            print("| \(k) | \(c.counts[k] ?? 0) |")
        }
        print("\nStage 2, every keyboard-plausible typo of the \(c.suppressed) flagged words (\(s.verifyTypos) typos):\n")
        for k in ["suppressed", "suggested", "related", "borderline"] { print("- \(k): \(f.counts[k] ?? 0)") }
        print("- cleared: \(s.cleared.map { "\($0[0]) (\($0[1]))" }.joined(separator: ", "))")
        print("\nFinal list: \(f.suppressed) words")
        print("- with >= 2 misses on unambiguous typos: \(f.suppressedWithUnambiguousEvidence)")
        print("- also absent from prefix completions: \(f.suppressedAlsoMissingFromCompletions)")
        print("- never produced by autocorrect: \(f.suppressedNeverAutocorrected)")
        print("- typos answered with an empty guess list: \(pct(f.suppressedEmptyListShare))")
        print("- lowercase: \(s.suppressedLowercase), capitalised: \(s.suppressedCapitalised)")
        for (label, k) in [("lowercase", s.control), ("capitalised", s.controlCapitalised)] {
            print("\n## Control (\(label)): eight typos, no early stop, on \(k.wordsTested) random words\n")
            print("Hit histogram (0...8): \(k.histogram.map(String.init).joined(separator: " "))")
            let all = k.perKind.reduce(0) { $0 + $1.trials }, hits = k.perKind.reduce(0) { $0 + $1.hits }
            print("Per-typo recovery, words that came back at least once:")
            for r in k.perKind {
                print("- \(r.kind): \(pct(r.rate)) (95% CI \(pct(r.low))-\(pct(r.high)), n=\(r.trials))")
            }
            print("- unambiguous typos: \(pct(k.unambiguousRate.rate)) (n=\(k.unambiguousRate.trials))")
            print("- all four kinds together: \(pct(Double(hits) / Double(max(all, 1))))")
            print("Control words flagged in stage 1: \(k.controlZeros.joined(separator: ", "))")
        }
        for (label, a) in [("Control words flagged in stage 1", s.auditControlZeros),
                           ("Random sample of the final list", s.auditSample),
                           ("Random sample of suggested words (base rate)", s.auditBaseRate)] {
            guard let a else { continue }
            print("\n## Audit: \(label) (n=\(a.size))\n")
            print("- topical: \(a.topical) = \(pct(Double(a.topical) / Double(max(a.size, 1))))")
            print("- lookalike: \(a.lookalike) (\(a.lookalikeWords.joined(separator: ", ")))")
            print("- no apparent reason: \(a.none) = \(pct(a.noneRate)) (95% CI \(pct(a.noneLow))-\(pct(a.noneHigh)))")
        }
        if let a = s.auditSample {
            print(String(format: "Projected over %d words: %.0f with no apparent reason (95%% CI %.0f-%.0f)",
                         f.suppressed, a.noneRate * Double(f.suppressed), a.noneLow * Double(f.suppressed), a.noneHigh * Double(f.suppressed)))
        }
        print("\n## Suppression rate by SCOWL size (smaller = more common)\n")
        for (size, v) in s.bySize.sorted(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }) {
            print("- size \(size): \(v[1]) of \(v[0]) = \(pct(Double(v[1]) / Double(max(v[0], 1))))")
        }
        print("\n## Categories (final list)\n")
        for (cat, n) in s.byCategory.sorted(by: { $0.value > $1.value }) { print("- \(cat): \(n)") }
        let cmp = s.comparison
        print("\n## Comparison\n")
        print("iOS keyboard list: \(cmp.iosPhrases) entries, \(cmp.iosWords) distinct words inside them")
        print("Final-list words that occur in some iOS entry: \(cmp.suppressedInIOSPhrase); not in any: \(cmp.suppressedNotInIOS)")
        print("Hunspell NOSUGGEST stems and their macOS verdicts:")
        for (w, v) in cmp.hunspellNoSuggest.sorted(by: { $0.key < $1.key }) { print("  \(w): \(v)") }
    }
}

/// `nosuggest check-readme`: every headline number in README.md must match
/// the published summary, so the prose can't drift from the data.
enum ReadmeCheck {
    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    static func run(_ opts: Options) {
        let summaryPath = opts.string("summary", "docs/data/summary-en.json")
        let readmePath = opts.string("readme", "README.md")
        guard let data = FileManager.default.contents(atPath: summaryPath),
              let s = try? JSONDecoder().decode(Report.Summary.self, from: data),
              let readme = try? String(contentsOfFile: readmePath, encoding: .utf8)
        else { fail("check-readme: cannot read \(summaryPath) or \(readmePath)") }

        var expected: [(String, String)] = [
            ("final list", grouped(s.final.suppressed)),
            ("words tested", grouped(s.census.tested)),
            ("stage 1 flagged", grouped(s.census.suppressed)),
            ("stage 2 typos", grouped(s.verifyTypos)),
            ("stage 1 typos", grouped(s.probeTypos)),
            ("cleared in stage 2", grouped(s.cleared.count)),
            ("suggested", grouped(s.census.counts["suggested"] ?? 0)),
            ("rejected", grouped(s.census.counts["rejected"] ?? 0)),
            ("not in any iOS entry", grouped(s.comparison.suppressedNotInIOS)),
            ("iOS entries", grouped(s.comparison.iosPhrases)),
            ("missing from completions", grouped(s.final.suppressedAlsoMissingFromCompletions)),
            ("control words", grouped(s.control.wordsTested)),
            ("empty guess lists", Report.pct(s.final.suppressedEmptyListShare)),
        ]
        if let a = s.auditSample {
            expected.append(("audit none rate", Report.pct(a.noneRate)))
        }
        var missing = 0
        for (label, value) in expected {
            let ok = readme.contains(value)
            if !ok { missing += 1 }
            print("\(ok ? "ok     " : "MISSING") \(label): \(value)")
        }
        if missing > 0 { fail("check-readme: \(missing) number(s) in the summary do not appear in \(readmePath)") }
    }
}
