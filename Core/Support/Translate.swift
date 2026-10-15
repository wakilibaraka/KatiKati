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
