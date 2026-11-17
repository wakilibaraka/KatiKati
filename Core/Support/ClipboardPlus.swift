import Foundation

/// Phase 22a: clipboard ignore-patterns and the toast policy. Pure and side-effect free; the monitor
/// (`Platform/Clipboard/ClipboardMonitor`) applies them. Settings (phase 12) edits the stored rules.
enum ClipboardIgnoreRules {
    /// One user rule: `/regex/` is a regular expression, anything else is a case-insensitive substring.
    enum Rule: Equatable, Sendable {
        case substring(String)
        case regex(String)
    }

    /// Parses one rule per line (blank lines dropped). A rule wrapped in slashes is a regex.
    static func parseLines(_ raw: String) -> [Rule] {
        raw.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.count > 2, trimmed.hasPrefix("/"), trimmed.hasSuffix("/") {
                return .regex(String(trimmed.dropFirst().dropLast()))
            }
            return .substring(trimmed.lowercased())
        }
    }

    /// True when `text` matches any rule: a match is never recorded (and so never toasted).
    static func matches(_ text: String, rules: [Rule]) -> Bool {
        guard !rules.isEmpty else { return false }
        let lowered = text.lowercased()
        for rule in rules {
            switch rule {
            case .substring(let needle):
                if lowered.contains(needle) { return true }
            case .regex(let pattern):
                guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                if re.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil { return true }
            }
        }
        return false
    }
}

/// Phase 22a: whether a recorded copy earns a toast. Nothing blank, nothing the preview would hide.
enum ClipboardToastPolicy {
    static func shouldToast(_ text: String) -> Bool { !ClipboardHistory.previewLine(text).isEmpty }
}

/// 53g — a file name for the image pasted into Finder that cannot overwrite anything:
/// `Clipboard Image.png`, then `Clipboard Image 2.png`, `Clipboard Image 3.png`… Names are compared
/// case-insensitively because APFS is case-insensitive by default, so "image.PNG" is already taken.
enum PasteImageNaming {
    static func uniqueName(base: String, fileExtension: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        let first = "\(base).\(fileExtension)"
        guard taken.contains(first.lowercased()) else { return first }
        var n = 2
        while taken.contains("\(base) \(n).\(fileExtension)".lowercased()) { n += 1 }
        return "\(base) \(n).\(fileExtension)"
    }
}

/// Droppy-inspired Slice D-ClipboardBadges: Metadata extraction and classification for clipboard items.
enum ClipboardCategory: String, CaseIterable, Sendable, Identifiable {
    case all
    case work
    case personal

    var id: String { rawValue }
}

struct ClipboardCardMetadata: Equatable, Sendable {
    enum ContentType: Equatable, Sendable {
        case text(charCount: Int, wordCount: Int)
        case hexColor(hex: String, color: DockRGBA)
        case image(width: Int, height: Int)
    }

    let contentType: ContentType
    let category: ClipboardCategory

    static func classify(text: String, originBundleID: String? = nil, workBundleIDs: Set<String> = []) -> ClipboardCardMetadata {
        if let parsedColor = parseHexColor(text) {
            return ClipboardCardMetadata(
                contentType: .hexColor(hex: parsedColor.hex, color: parsedColor.color),
                category: resolveCategory(originBundleID: originBundleID, workBundleIDs: workBundleIDs)
            )
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split { $0.isWhitespace || $0.isNewline }
        return ClipboardCardMetadata(
            contentType: .text(charCount: trimmed.count, wordCount: words.count),
            category: resolveCategory(originBundleID: originBundleID, workBundleIDs: workBundleIDs)
        )
    }

    static func classifyImage(width: Int, height: Int, originBundleID: String? = nil, workBundleIDs: Set<String> = []) -> ClipboardCardMetadata {
        ClipboardCardMetadata(
            contentType: .image(width: max(0, width), height: max(0, height)),
            category: resolveCategory(originBundleID: originBundleID, workBundleIDs: workBundleIDs)
        )
    }

    static func resolveCategory(originBundleID: String?, workBundleIDs: Set<String>) -> ClipboardCategory {
        guard let id = originBundleID?.lowercased(), !id.isEmpty else { return .personal }
        let work = Set(workBundleIDs.map { $0.lowercased() })
        return work.contains(id) ? .work : .personal
    }

    /// Validates #RGB, #RRGGBB, or #RRGGBBAA (with or without '#')
    static func parseHexColor(_ raw: String) -> (hex: String, color: DockRGBA)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") || trimmed.count == 6 else { return nil }
        let clean = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard clean.count == 3 || clean.count == 6 || clean.count == 8 else { return nil }
        guard clean.allSatisfy({ $0.isHexDigit }) else { return nil }

        if clean.count == 6 {
            guard let val = UInt64(clean, radix: 16) else { return nil }
            let r = CGFloat((val >> 16) & 0xFF) / 255.0
            let g = CGFloat((val >> 8) & 0xFF) / 255.0
            let b = CGFloat(val & 0xFF) / 255.0
            return (hex: "#" + clean.uppercased(), color: DockRGBA(r: r, g: g, b: b, a: 1.0))
        } else if clean.count == 3 {
            var expanded = ""
            for ch in clean { expanded.append(ch); expanded.append(ch) }
            guard let val = UInt64(expanded, radix: 16) else { return nil }
            let r = CGFloat((val >> 16) & 0xFF) / 255.0
            let g = CGFloat((val >> 8) & 0xFF) / 255.0
            let b = CGFloat(val & 0xFF) / 255.0
            return (hex: "#" + expanded.uppercased(), color: DockRGBA(r: r, g: g, b: b, a: 1.0))
        } else if clean.count == 8 {
            guard let val = UInt64(clean, radix: 16) else { return nil }
            let r = CGFloat((val >> 24) & 0xFF) / 255.0
            let g = CGFloat((val >> 16) & 0xFF) / 255.0
            let b = CGFloat((val >> 8) & 0xFF) / 255.0
            let a = CGFloat(val & 0xFF) / 255.0
            return (hex: "#" + clean.uppercased(), color: DockRGBA(r: r, g: g, b: b, a: a))
        }
        return nil
    }
}

/// Slice CS-3: compact content badge for Notch Copy Toast & Dock/EdgeBar Clipboard Micro-Tile.
enum ClipboardToastBadge {
    static let dockTileKey = "com.katikati.clipboard.dockTile"

    static func badge(for text: String, linkCleaned: Bool = false) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = ClipboardCardMetadata.parseHexColor(trimmed) {
            return parsed.hex
        }
        if linkCleaned {
            return "Link Cleaned"
        }
        let lower = trimmed.lowercased()
        if (lower.hasPrefix("http://") || lower.hasPrefix("https://")),
           URL(string: trimmed) != nil {
            return "URL"
        }
        return "\(text.count) ch"
    }
}

/// Slice MC-1 — the Clipboard tab's stored switches, named once so the pane, the monitor and the flyout agree.
enum ClipboardSettingsKeys {
    static let pasteAutomatically = "com.katikati.clipboard.pasteAutomatically"
    static let plainTextByDefault = "com.katikati.clipboard.plainTextByDefault"
    static let pollingIntervalMS = "com.katikati.clipboard.pollingIntervalMS"
    static let historyLimit = "com.katikati.clipboard.historyLimit"
    static let sortBy = "com.katikati.clipboard.sortBy"
    static let ignoreConcealed = "com.katikati.clipboard.ignoreConcealed"
    static let ignoreAutoGenerated = "com.katikati.clipboard.ignoreAutoGenerated"
    static let ignoreUniversal = "com.katikati.clipboard.ignoreUniversal"
    static let showFooterShortcuts = "com.katikati.clipboard.showFooterShortcuts"
    static let showPinShortcuts = "com.katikati.clipboard.showPinShortcuts"
    static let popupPosition = "com.katikati.clipboard.popupPosition"
}

/// Slice MC-1 — how the history list is ordered.
enum ClipboardSortOrder: String, CaseIterable, Identifiable {
    case lastCopied, firstCopied, mostUsed
    var id: String { rawValue }
}

/// Slice MC-1 — where the clipboard popup opens.
enum ClipboardPopupPosition: String, CaseIterable, Identifiable {
    case atCursor, screenCenter, underBar
    var id: String { rawValue }
}
