import Foundation

/// Pure file-name rules for notes written to the sync folder (Phase 7A-6c). Names are cosmetic —
/// identity lives in the header — so they only need to be legal, readable and unique.
enum NoteFileName {
    static let fileExtension = "md"
    static let maxStemLength = 60

    /// `Title.md`, or `Title 2.md`, `Title 3.md`… when the stem is taken (case-insensitive).
    static func make(title: String, existing: Set<String>, fallbackStem: String = "Note") -> String {
        let stem = sanitizedStem(title, fallback: fallbackStem)
        let taken = Set(existing.map { $0.lowercased() })
        var candidate = "\(stem).\(fileExtension)"
        var n = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(stem) \(n).\(fileExtension)"
            n += 1
        }
        return candidate
    }

    static func sanitizedStem(_ title: String, fallback: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        let cleaned = title.unicodeScalars.map { illegal.contains($0) ? " " : Character($0) }
        var stem = String(cleaned).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        stem = String(stem.prefix(maxStemLength)).trimmingCharacters(in: .whitespaces)
        while stem.hasPrefix(".") { stem.removeFirst() }       // never produce a hidden file
        return stem.isEmpty ? fallback : stem
    }

    /// Stem of a file name (`"Groceries.md"` → `"Groceries"`).
    static func stem(of fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }
}
