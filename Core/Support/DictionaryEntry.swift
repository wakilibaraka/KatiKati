import Foundation

/// Dictionary + Terminal step 1: a structured dictionary entry parsed from `DCSCopyTextDefinition`'s flat text
/// (`headword |phonetic| noun 1 sense: example | example 2 sense … ORIGIN 1754: …`). Pure Foundation — no
/// CoreServices, no AppKit — so the shape is unit-tested against payload fixtures. Tolerant by design: an
/// unexpected shape still yields a headword and one plain sense, so the panel always has something to show.
/// `DictionaryCardModel` (Translate.swift) stays the model of the selection card; this one feeds the panel.
struct DictionaryEntry: Equatable, Sendable {
    struct Sense: Equatable, Sendable {
        var text: String
        var examples: [String]
    }

    struct Block: Equatable, Sendable {
        /// "noun", "verb", …; nil when the payload names no part of speech.
        var partOfSpeech: String?
        var senses: [Sense]
    }

    var headword: String
    var phonetic: String?
    var blocks: [Block]
    var origin: String?

    /// Every sense text, in order, across parts of speech.
    var senseTexts: [String] { blocks.flatMap { $0.senses.map(\.text) } }

    /// What "Copy Definition" puts on the pasteboard: the headword, then one numbered line per sense.
    var copyText: String {
        var lines = [headword]
        for block in blocks {
            if let pos = block.partOfSpeech { lines.append(pos) }
            for (index, sense) in block.senses.enumerated() {
                lines.append("\(index + 1). \(sense.text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static let partsOfSpeech: [String] = [
        "noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction",
        "interjection", "exclamation", "determiner", "abbreviation", "prefix", "suffix",
    ]

    /// Parses a raw payload; nil only when it has no usable text at all.
    static func parse(headword fallback: String, payload: String?) -> DictionaryEntry? {
        guard let payload else { return nil }
        let flat = payload.split(whereSeparator: \.isNewline).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !flat.isEmpty else { return nil }

        let (body, origin) = splitOrigin(flat)
        let (head, phonetic, rest) = splitHead(body)
        let blocks = parseBlocks(rest)
        let word = head.isEmpty ? fallback : head
        guard !blocks.isEmpty || origin != nil || !head.isEmpty else { return nil }
        return DictionaryEntry(headword: word, phonetic: phonetic, blocks: blocks, origin: origin)
    }

    // MARK: - Pieces

    /// `… ORIGIN 1754: …` — the uppercase marker starts the etymology, which runs to the end.
    private static func splitOrigin(_ text: String) -> (body: String, origin: String?) {
        guard let range = text.range(of: "ORIGIN ") else { return (text, nil) }
        let body = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let origin = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (body, origin.isEmpty ? nil : origin)
    }

    /// `headword |phonetic| rest`. Without a pipe pair the head is the first word and the rest follows it.
    private static func splitHead(_ text: String) -> (head: String, phonetic: String?, rest: String) {
        let parts = text.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3 {
            let phonetic = parts[1].trimmingCharacters(in: .whitespaces)
            return (parts[0].trimmingCharacters(in: .whitespaces),
                    phonetic.isEmpty ? nil : phonetic,
                    parts[2].trimmingCharacters(in: .whitespaces))
        }
        return ("", nil, text)
    }

    /// Splits `rest` at each part-of-speech word; text before the first one becomes an unlabeled block.
    private static func parseBlocks(_ rest: String) -> [Block] {
        let words = rest.split(separator: " ").map(String.init)
        var blocks: [Block] = []
        var pos: String?
        var chunk: [String] = []

        func flush() {
            let text = chunk.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            chunk = []
            guard !text.isEmpty else { return }
            blocks.append(Block(partOfSpeech: pos, senses: parseSenses(text)))
        }

        for (index, word) in words.enumerated() {
            let isPOS = partsOfSpeech.contains(word)
                && (index == 0 || chunk.isEmpty || words[index - 1].hasSuffix("."))
                && startsSenseText(after: index, in: words)
            if isPOS {
                flush()
                pos = word
            } else {
                chunk.append(word)
            }
        }
        flush()
        return blocks
    }

    /// A part-of-speech word only opens a block when real text follows (so "the noun phrase" inside a sense
    /// is not mistaken for a heading): the next word must exist and not be punctuation-led.
    private static func startsSenseText(after index: Int, in words: [String]) -> Bool {
        guard index + 1 < words.count else { return false }
        guard let first = words[index + 1].first else { return false }
        return first.isLetter || first.isNumber
    }

    /// Splits `1 sense: example | example 2 sense …`; numbering must run 1, 2, 3… so a stray number in the text
    /// never splits a sense. Without numbers the whole text is one sense.
    private static func parseSenses(_ text: String) -> [Sense] {
        var pieces: [[String]] = []
        for word in text.split(separator: " ").map(String.init) {
            if word == String(pieces.count + 1) {
                pieces.append([])
            } else if pieces.isEmpty {
                pieces.append([word])
            } else {
                pieces[pieces.count - 1].append(word)
            }
        }
        return pieces.compactMap { sense(from: $0.joined(separator: " ")) }
    }

    private static func sense(from text: String) -> Sense? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let colon = trimmed.firstIndex(of: ":") else { return Sense(text: trimmed, examples: []) }
        let definition = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
        let examples = trimmed[trimmed.index(after: colon)...]
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "."))) }
            .filter { !$0.isEmpty }
        return Sense(text: definition.isEmpty ? trimmed : definition, examples: examples)
    }
}
