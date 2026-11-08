import Foundation
import NoSuggestCore

let usage = """
nosuggest: find words the macOS spell checker accepts but will not suggest.

USAGE
  nosuggest word <word>...                 explain the verdict for each word
  nosuggest probe --lexicon <file> [--neighbors <file>] [--jobs N] [--out <file>]
                                           probe every word in a lexicon (JSON lines)
  nosuggest probe ... --neighbourhood 1     exhaustive pass: every keyboard-plausible
                                           single edit of each word (verification)
  nosuggest control --lexicon <file> [--neighbors <file>] [--sample N] [--seed S]
                    [--jobs N] [--out <file>]
                                           full battery on a random sample (no early exit)
  nosuggest report [--data <dir>] [--out <dir>]
                                           summarise a census for the web explorer
  nosuggest concepts [--file data/concepts.tsv]
                                           same concepts, every keyboard-plausible typo,
                                           across languages, as JSON
  nosuggest guesses <typo=word>...         raw guesses for typos, as JSON
  nosuggest check-readme                   fail if README numbers drift from docs/data
  nosuggest env                            print OS, checker and user-dictionary details

OPTIONS
  --language <code>   spell-checker language (default: en)
  --battery N         typos per word (default 8)
  --neighbors <file>  word list used to judge whether a typo is ambiguous
                      (default: the lexicon itself)

Lexicon files hold one word per line; anything after a tab is ignored.
"""

struct Options {
    var command = ""
    var positional: [String] = []
    var flags: [String: String] = [:]

    init(_ argv: [String]) {
        var it = argv.dropFirst().makeIterator()
        command = it.next() ?? ""
        while let a = it.next() {
            if a.hasPrefix("--") {
                flags[String(a.dropFirst(2))] = it.next() ?? ""
            } else {
                positional.append(a)
            }
        }
    }

    func int(_ k: String, _ d: Int) -> Int { flags[k].flatMap(Int.init) ?? d }
    func string(_ k: String, _ d: String) -> String { flags[k] ?? d }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("nosuggest: \(msg)\n".utf8))
    exit(2)
}

func readWords(_ path: String) -> [String] {
    guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
    return s.split(whereSeparator: \.isNewline).compactMap { line in
        let w = line.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? ""
        return w.isEmpty || w.hasPrefix("#") ? nil : w
    }
}

let opts = Options(CommandLine.arguments)
let language = opts.string("language", "en")
var policy = ProbePolicy()
policy.battery = opts.int("battery", policy.battery)

let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return e
}()

func emit(_ r: WordResult, to out: FileHandle) {
    var d = try! encoder.encode(r)
    d.append(0x0A)
    out.write(d)
}

/// Runs `words` through the checker. The spell server answers roughly 100
/// guesses a second per client and about 175 a second in total, so the work
/// is split across child processes, each with its own NSSpellChecker.
func runSharded(words: [String], neighborsPath: String?, outPath: String?, jobs: Int, extraArgs: [String]) {
    let out: FileHandle
    if let p = outPath {
        FileManager.default.createFile(atPath: p, contents: nil)
        out = FileHandle(forWritingAtPath: p)!
    } else {
        out = .standardOutput
    }

    if jobs <= 1 {
        let lex = Lexicon(neighborsPath.map(readWords) ?? words)
        let prober = Prober(oracle: AppleSpellOracle(language: language), lexicon: lex, policy: policy)
        let started = Date()
        for (i, w) in words.enumerated() {
            emit(prober.probe(w), to: out)
            if (i + 1) % 2000 == 0 {
                let rate = Double(i + 1) / Date().timeIntervalSince(started)
                FileHandle.standardError.write(Data(String(format: "  %d/%d words, %.0f words/s\n", i + 1, words.count, rate).utf8))
            }
        }
        return
    }

    // Shard by round-robin so every child sees the same mix of word lengths.
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nosuggest-\(getpid())")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    var children: [(Process, URL)] = []
    for j in 0..<jobs {
        let shard = words.enumerated().filter { $0.offset % jobs == j }.map(\.element)
        let inURL = tmp.appendingPathComponent("in-\(j).txt")
        let outURL = tmp.appendingPathComponent("out-\(j).jsonl")
        try! shard.joined(separator: "\n").write(to: inURL, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = Bundle.main.executableURL
        var args = ["probe", "--lexicon", inURL.path, "--out", outURL.path, "--jobs", "1",
                    "--language", language, "--battery", String(policy.battery)]
        args += ["--neighbors", neighborsPath ?? writeTemp(words, tmp)]
        args += extraArgs
        p.arguments = args
        try! p.run()
        children.append((p, outURL))
    }
    for (p, _) in children { p.waitUntilExit() }
    for (p, url) in children {
        guard p.terminationStatus == 0 else { fail("worker exited with status \(p.terminationStatus)") }
        out.write(try! Data(contentsOf: url))
    }
    try? FileManager.default.removeItem(at: tmp)
}

var tempNeighbors: String?
func writeTemp(_ words: [String], _ dir: URL) -> String {
    if let t = tempNeighbors { return t }
    let url = dir.appendingPathComponent("neighbors.txt")
    try! words.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    tempNeighbors = url.path
    return url.path
}

switch opts.command {
case "word":
    guard !opts.positional.isEmpty else { fail("word: give at least one word") }
    var p = policy
    p.earlyExit = false
    p.minLength = 3
    let defaultNeighbors = "lexicon/neighbors-en.txt"
    let neighborsPath = opts.flags["neighbors"]
        ?? (FileManager.default.fileExists(atPath: defaultNeighbors) ? defaultNeighbors : nil)
    let lex = Lexicon(neighborsPath.map(readWords) ?? [])
    let prober = Prober(oracle: AppleSpellOracle(language: language), lexicon: lex, policy: p)
    for w in opts.positional {
        let r = prober.probe(w)
        let hits = r.trials.filter(\.hit).count
        print("\(w)  ->  \(r.verdict.rawValue.uppercased())   (\(hits)/\(r.trials.count) typos brought it back)")
        for t in r.trials {
            let shown = t.guesses.prefix(5).joined(separator: ", ")
            let mark = t.hit ? "yes" : (t.related ? "~  " : " no")
            print(String(format: "  %@  %-14@ %-13@ [%@]", mark, t.typo as NSString, t.kind.rawValue as NSString, shown as NSString))
        }
        if let c = r.completionHit { print("  completions of \"\(w.dropLast())\" include it: \(c ? "yes" : "no")") }
        if let c = r.correctionHit { print("  autocorrect ever produces it: \(c ? "yes" : "no")") }
        print("")
    }

case "probe":
    guard let lexPath = opts.flags["lexicon"] else { fail("probe: --lexicon is required") }
    let words = readWords(lexPath)
    let jobs = opts.int("jobs", 4)
    if jobs > 1 { FileHandle.standardError.write(Data("probing \(words.count) words with \(jobs) workers\n".utf8)) }
    var extra: [String] = []
    if opts.flags["full"] != nil { policy.earlyExit = false; extra += ["--full", "1"] }
    if opts.flags["neighbourhood"] != nil { policy.fullNeighbourhood = true; extra += ["--neighbourhood", "1"] }
    runSharded(words: words, neighborsPath: opts.flags["neighbors"], outPath: opts.flags["out"], jobs: jobs, extraArgs: extra)

case "control":
    guard let lexPath = opts.flags["lexicon"] else { fail("control: --lexicon is required") }
    let all = readWords(lexPath).filter { $0.count >= policy.minLength }
    var rng = Stats.SplitMix64(seed: UInt64(opts.int("seed", 20261108)))
    let n = min(opts.int("sample", 2000), all.count)
    let sample = Array(all.shuffled(using: &rng).prefix(n))
    policy.earlyExit = false
    FileHandle.standardError.write(Data("control: full battery on \(sample.count) random words\n".utf8))
    runSharded(words: sample, neighborsPath: opts.flags["neighbors"] ?? lexPath, outPath: opts.flags["out"],
               jobs: opts.int("jobs", 4), extraArgs: ["--full", "1"])

case "guesses":
    // nosuggest guesses typo=word ... -> JSON with the checker's raw answers.
    guard !opts.positional.isEmpty else { fail("guesses: give typo=word pairs") }
    let o = AppleSpellOracle(language: language)
    var rows: [[String: Any]] = []
    for pair in opts.positional {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        let typo = parts[0]
        var row: [String: Any] = ["typo": typo, "guesses": o.guesses(for: typo)]
        if parts.count == 2 {
            row["word"] = parts[1]
            row["accepted"] = o.isAccepted(parts[1])
        }
        rows.append(row)
    }
    let d = try! JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
    print(String(decoding: d, as: UTF8.self))

case "concepts":
    // One row per concept, one column per language: the same idea probed
    // with the full battery in every language the file lists.
    let path = opts.string("file", "data/concepts.tsv")
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
    let lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    guard let header = lines.first, header.count > 1 else { fail("concepts: empty file") }
    var p = policy
    p.earlyExit = false
    p.minLength = 3
    p.fullNeighbourhood = true   // every keyboard-plausible typo, as in stage 2
    var probers: [String: Prober] = [:]
    var rows: [[String: Any]] = []
    for line in lines.dropFirst() where line.count == header.count {
        var cells: [String: Any] = [:]
        for (i, lang) in header.enumerated().dropFirst() {
            let prober = probers[lang] ?? Prober(oracle: AppleSpellOracle(language: lang), lexicon: Lexicon([]), policy: p)
            probers[lang] = prober
            let r = prober.probe(line[i])
            cells[lang] = ["word": line[i], "verdict": r.verdict.rawValue,
                           "hits": r.trials.filter(\.hit).count, "trials": r.trials.count,
                           "example": r.trials.first.map { [$0.typo] + $0.guesses } ?? []]
        }
        rows.append(["concept": line[0], "cells": cells])
    }
    let out: [String: Any] = ["languages": Array(header.dropFirst()), "rows": rows]
    let d = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    print(String(decoding: d, as: UTF8.self))

case "report":
    Report.run(opts)

case "check-readme":
    ReadmeCheck.run(opts)

case "env":
    let pi = ProcessInfo.processInfo
    let o = AppleSpellOracle(language: language)
    let info: [String: Any] = [
        "os": pi.operatingSystemVersionString,
        "language": language,
        "available_languages": o.checker.availableLanguages,
        "user_dictionary_words": o.userWordCount,
    ]
    let d = try! JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: d, as: UTF8.self))

case "", "-h", "--help", "help":
    print(usage)

default:
    fail("unknown command '\(opts.command)'\n\n\(usage)")
}
