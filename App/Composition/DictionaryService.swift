import CoreServices

/// Phase 23b: an offline definition from the system dictionaries (`DCSCopyTextDefinition`). A local
/// lookup only — no network, no keys.
enum DictionaryService {
    static func define(_ word: String) -> String? {
        let range = CFRange(location: 0, length: word.utf16.count)
        guard let definition = DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() else { return nil }
        return definition as String
    }
}
