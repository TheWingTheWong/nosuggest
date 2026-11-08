import AppKit
import NoSuggestCore

/// Answers the probe's questions with the system spell checker, the same
/// NSSpellChecker that TextEdit, Mail, Notes, Pages and Safari text fields use.
///
/// Every call passes an explicit language and document tag 0, so results do
/// not depend on automatic language detection or on per-document ignored
/// words. Words the user has taught the checker ("Learn Spelling") do affect
/// results; `nosuggest env` prints how many there are.
final class AppleSpellOracle: SpellOracle {
    let checker = NSSpellChecker.shared
    let language: String

    init(language: String) {
        self.language = language
        checker.automaticallyIdentifiesLanguages = false
        _ = checker.setLanguage(language)
    }

    private func range(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    func isAccepted(_ word: String) -> Bool {
        let r = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                      inSpellDocumentWithTag: 0, wordCount: nil)
        return r.location == NSNotFound
    }

    func guesses(for typo: String) -> [String] {
        checker.guesses(forWordRange: range(typo), in: typo, language: language, inSpellDocumentWithTag: 0) ?? []
    }

    func completions(for prefix: String) -> [String] {
        checker.completions(forPartialWordRange: range(prefix), in: prefix, language: language,
                            inSpellDocumentWithTag: 0) ?? []
    }

    func correction(for typo: String) -> String? {
        checker.correction(forWordRange: range(typo), in: typo, language: language, inSpellDocumentWithTag: 0)
    }

    /// Words the current user has added with "Learn Spelling".
    var userWordCount: Int { checker.userDictionaryWordCount }
}

extension NSSpellChecker {
    var userDictionaryWordCount: Int {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Spelling/LocalDictionary")
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return s.split(whereSeparator: \.isNewline).count
    }
}
