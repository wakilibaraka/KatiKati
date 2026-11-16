import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Phase 23a: the pure core of Translate & Define. Decides whether a selection is worth looking up,
/// guesses its language, gates the offline translation half by OS version, and trims a dictionary
/// payload into a card model. No AppKit, no AX, no network.

/// A text selection to define / translate.
struct TranslateRequest: Equatable, Sendable {
    var text: String
    /// BCP-47 language guess (nil when unknown). Best-effort, so tests assert only the heuristics.
    var sourceLanguage: String?
    /// False for blank text, URLs and bare numbers — nothing worth defining or translating.
    var isTranslatable: Bool

    static func detect(_ raw: String) -> TranslateRequest {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return TranslateRequest(text: "", sourceLanguage: nil, isTranslatable: false) }
        let worth = isWorthTranslating(text)
        return TranslateRequest(text: text, sourceLanguage: worth ? language(of: text) : nil, isTranslatable: worth)
    }

    /// Letters are required; a URL, a bare number or punctuation-only text is not worth a lookup.
    static func isWorthTranslating(_ text: String) -> Bool {
        guard text.contains(where: \.isLetter) else { return false }
        if text.contains("://") { return false }
        // A single "word.word" with a letters-only tail looks like a domain, not prose.
        if !text.contains(" "), text.contains(".") {
            let tail = text.split(separator: ".").last.map(String.init) ?? ""
            if (2...24).contains(tail.count), tail.allSatisfy(\.isLetter) { return false }
        }
        return true
    }

    private static func language(of text: String) -> String? {
        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
        #else
        return nil
        #endif
    }
}

/// Phase 23a: a dictionary result trimmed from `DCSCopyTextDefinition` into a headword + sense lines.
struct DictionaryCardModel: Equatable, Sendable {
    var headword: String
    var senses: [String]

    /// The raw payload is `headword | phonetics | …` on the first line, senses after. Tolerant by design:
    /// an unexpected shape still yields the headword, so a card always has something to show.
    static func parse(headword fallback: String, payload: String?) -> DictionaryCardModel? {
        guard let payload else { return nil }
        let lines = payload.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return nil }
        // Split the raw first line so a blank head still counts as blank (trimming first would drop it).
        let parts = first.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let head = parts.first ?? ""
        var senses = lines.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if senses.isEmpty, parts.count > 1 {
            let rest = parts.dropFirst().joined(separator: " | ").trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { senses = [rest] }
        }
        return DictionaryCardModel(headword: head.isEmpty ? fallback : head, senses: senses)
    }
}

// MARK: - Droppy-Inspired Slice C-DropClip: Selection Action Pill Policy

enum SelectionAction: String, CaseIterable, Identifiable, Sendable {
    case copy
    case cut
    case paste
    case search
    case translate
    case ai

    var id: String { rawValue }
}

struct SelectionStats: Equatable, Sendable {
    let charCount: Int
    let wordCount: Int
}

enum DropClipPolicy {
    static let minTextLength = 2
    static let maxTextLength = 10_000
    static let enabledKey = "com.katikati.dropclip.enabled"

    static let defaultExcludedBundleIDs: Set<String> = [
        "com.agilebits.onepassword",
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess"
    ]

    static func stats(for text: String) -> SelectionStats {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split { $0.isWhitespace || $0.isNewline }
        return SelectionStats(charCount: trimmed.count, wordCount: words.count)
    }

    /// Evaluates whether the floating action pill should be presented for a selection.
    /// Strictly suppressed when:
    /// 1. Secure event input is enabled (passwords, sensitive fields)
    /// 2. Frontmost app is in the excluded bundle ID list (password managers)
    /// 3. Text length is below minTextLength or exceeds maxTextLength
    /// 4. Text consists entirely of whitespace
    static func shouldPresent(
        text: String,
        originBundleID: String?,
        isSecureInput: Bool,
        excludedBundleIDs: Set<String> = defaultExcludedBundleIDs
    ) -> Bool {
        guard !isSecureInput else { return false }

        if let bundleID = originBundleID?.lowercased() {
            let excluded = Set(excludedBundleIDs.map { $0.lowercased() })
            if excluded.contains(bundleID) { return false }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minTextLength && trimmed.count <= maxTextLength else {
            return false
        }

        return true
    }

    /// Evaluates which actions are relevant for the given selected text.
    static func actions(for text: String) -> [SelectionAction] {
        guard TranslateRequest.isWorthTranslating(text) else {
            return [.copy, .search]
        }
        return [.copy, .search, .translate, .ai]
    }
}
