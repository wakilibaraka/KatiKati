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

    static let defaultWorkBundleIDs: Set<String> = [
        "com.apple.dt.xcode",
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "dev.warp.warp-stable",
        "com.mitchellh.ghostty",
        "com.microsoft.vscode",
        "com.todesktop.230313mzl4w4u92",
        "com.tinyspeck.slackmacgap",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "us.zoom.xos",
        "notion.id",
        "com.linear",
        "com.figma.desktop",
        "md.obsidian",
        "com.apple.mail",
        "com.apple.ical",
        "com.apple.iwork.keynote",
        "com.apple.iwork.numbers",
        "com.apple.iwork.pages",
        "com.microsoft.word",
        "com.microsoft.excel",
        "com.microsoft.powerpoint"
    ]

    let contentType: ContentType
    let category: ClipboardCategory

    static func classify(
        text: String,
        originBundleID: String? = nil,
        workBundleIDs: Set<String> = defaultWorkBundleIDs
    ) -> ClipboardCardMetadata {
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

    static func classifyImage(
        width: Int,
        height: Int,
        originBundleID: String? = nil,
        workBundleIDs: Set<String> = defaultWorkBundleIDs
    ) -> ClipboardCardMetadata {
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
    static let soundsKey = "com.katikati.clipboard.sounds"
    static let soundOnCopy = "com.katikati.clipboard.sound.copy"
    static let soundOnPaste = "com.katikati.clipboard.sound.paste"
    static let soundOnHistoryUpdated = "com.katikati.clipboard.sound.historyUpdated"
    static let soundOnLinkCleaned = "com.katikati.clipboard.sound.linkCleaned"
    static let soundVolume = "com.katikati.clipboard.sound.volume"
    static let notchToastKey = "com.katikati.clipboard.notchToast"
}

/// T1.2: granular optional audio cues for clipboard copy, paste, history update, and link cleaning.
enum ClipboardAudioEvent: String, CaseIterable, Sendable {
    case copy, paste, historyUpdated, linkCleaned

    var defaultsKey: String {
        switch self {
        case .copy: return ClipboardSettingsKeys.soundOnCopy
        case .paste: return ClipboardSettingsKeys.soundOnPaste
        case .historyUpdated: return ClipboardSettingsKeys.soundOnHistoryUpdated
        case .linkCleaned: return ClipboardSettingsKeys.soundOnLinkCleaned
        }
    }

    var systemSoundName: String {
        switch self {
        case .copy, .historyUpdated: return "Tink"
        case .paste: return "Pop"
        case .linkCleaned: return "Morse"
        }
    }
}

enum ClipboardAudioPolicy {
    static let defaultVolume: Float = 0.45
    static let volumeRange: ClosedRange<Float> = 0.1...1.0

    static func isEnabled(_ event: ClipboardAudioEvent, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: ClipboardSettingsKeys.soundsKey) as? Bool ?? true else { return false }
        return defaults.object(forKey: event.defaultsKey) as? Bool ?? true
    }

    static func soundName(for event: ClipboardAudioEvent, defaults: UserDefaults = .standard) -> String? {
        isEnabled(event, defaults: defaults) ? event.systemSoundName : nil
    }

    static func volume(defaults: UserDefaults = .standard) -> Float {
        guard defaults.object(forKey: ClipboardSettingsKeys.soundVolume) != nil else { return defaultVolume }
        return min(max(defaults.float(forKey: ClipboardSettingsKeys.soundVolume), volumeRange.lowerBound), volumeRange.upperBound)
    }
}

struct ClipboardPollResolution: Equatable, Sendable {
    var finalText: String
    var didCleanLink: Bool
    var shouldRewritePasteboard: Bool
    var shouldRecordHistory: Bool
    var audioEvent: ClipboardAudioEvent?
}

/// T1.2: single-pass pasteboard processor combining URL tracking-parameter stripping and history recording.
enum ClipboardPasteboardProcessor {
    static func process(text: String, isRecording: Bool, cleanLinks: Bool) -> ClipboardPollResolution {
        if cleanLinks, let cleaned = URLCleaner.clean(text) {
            return ClipboardPollResolution(
                finalText: cleaned,
                didCleanLink: true,
                shouldRewritePasteboard: true,
                shouldRecordHistory: isRecording,
                audioEvent: .linkCleaned
            )
        }
        return ClipboardPollResolution(
            finalText: text,
            didCleanLink: false,
            shouldRewritePasteboard: false,
            shouldRecordHistory: isRecording,
            audioEvent: isRecording ? .historyUpdated : nil
        )
    }
}

/// NP-1: the notch toast for a recorded copy is off unless the user asks for it (Clipboard → Behaviour →
/// "Copy & Paste Glimpse Notifications"). One reader for the three delivery sites and the settings row, so an
/// unset key, an explicit off and the registration default can never disagree.
enum ClipboardToastDefaults {
    static let enabledByDefault = false

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: ClipboardSettingsKeys.notchToastKey) as? Bool ?? enabledByDefault
    }
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

/// Slice MC-2 — the pasteboard filter Maccy applies before anything is recorded. Pure: the monitor hands it the
/// types, the source bundle and the text; the page's Privacy toggles become `Rules`.
enum MaccyPasteboardFilter {
    /// Concealed (password fields), transient (clipboard managers' own scratch writes) and the 1Password marker.
    static let concealedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.agilebits.onepassword",
    ]
    static let autoGeneratedTypes: Set<String> = ["org.nspasteboard.AutoGeneratedType"]
    /// Universal Clipboard: a copy that arrived from another device over Handoff.
    static let universalTypes: Set<String> = ["com.apple.is-remote-clipboard"]

    struct Rules: Equatable, Sendable {
        var ignoreConcealed = true
        var ignoreAutoGenerated = true
        var ignoreUniversal = false
        var ignoredBundleIDs: [String] = []
        var ignoredPatterns: [String] = []

        init(ignoreConcealed: Bool = true,
             ignoreAutoGenerated: Bool = true,
             ignoreUniversal: Bool = false,
             ignoredBundleIDs: [String] = [],
             ignoredPatterns: [String] = []) {
            self.ignoreConcealed = ignoreConcealed
            self.ignoreAutoGenerated = ignoreAutoGenerated
            self.ignoreUniversal = ignoreUniversal
            self.ignoredBundleIDs = ignoredBundleIDs
            self.ignoredPatterns = ignoredPatterns
        }
    }

    /// True when the copy is safe to remember. A bundle match and a pattern match are both refusals; patterns are
    /// case-insensitive substrings, like the existing `ClipboardIgnoreRules` rules.
    static func shouldRecord(types: [String],
                             sourceBundleID: String? = nil,
                             text: String? = nil,
                             rules: Rules = Rules()) -> Bool {
        let set = Set(types)
        if rules.ignoreConcealed, !set.isDisjoint(with: concealedTypes) { return false }
        if rules.ignoreAutoGenerated, !set.isDisjoint(with: autoGeneratedTypes) { return false }
        if rules.ignoreUniversal, !set.isDisjoint(with: universalTypes) { return false }
        if let bundle = sourceBundleID?.lowercased(),
           rules.ignoredBundleIDs.contains(where: { $0.lowercased() == bundle }) { return false }
        if let text, !text.isEmpty, !rules.ignoredPatterns.isEmpty {
            let lowered = text.lowercased()
            if rules.ignoredPatterns.contains(where: { lowered.contains($0.lowercased()) }) { return false }
        }
        return true
    }
}

/// Slice MC-2 — the three capture states. `skipNextCopy` is a one-shot latch: it refuses one copy and drops back to
/// `active` on its own, so the button can never leave recording switched off by accident.
enum ClipboardCaptureMode: Equatable, Sendable {
    case active
    case paused
    case skipNextCopy

    /// What to do with the copy that just happened, and the mode that follows it.
    func shouldRecordCopy() -> (record: Bool, nextMode: ClipboardCaptureMode) {
        switch self {
        case .active: return (true, .active)
        case .paused: return (false, .paused)
        case .skipNextCopy: return (false, .active)
        }
    }

    var isPaused: Bool { self == .paused }
    var isSkippingNextCopy: Bool { self == .skipNextCopy }
}

/// Slice MC-2 — ⌘1–⌘9 pin slots, Maccy-style (`#1611`): a pinned item keeps the number it already had, gaps left by
/// unpinned items are refilled in display order, and a tenth pin is unnumbered rather than renumbered past nine.
enum MaccyPinShortcutAssigner {
    static let maxSlot = 9

    static func assign(pinnedIDs: [UUID], previous: [UUID: Int] = [:]) -> [UUID: Int] {
        var slots: [UUID: Int] = [:]
        var used = Set<Int>()
        for id in pinnedIDs {
            guard let slot = previous[id], (1...maxSlot).contains(slot), !used.contains(slot) else { continue }
            slots[id] = slot
            used.insert(slot)
        }
        for id in pinnedIDs where slots[id] == nil {
            guard let slot = (1...maxSlot).first(where: { !used.contains($0) }) else { break }
            slots[id] = slot
            used.insert(slot)
        }
        return slots
    }

    static func entryID(forSlot slot: Int, in slots: [UUID: Int]) -> UUID? {
        guard (1...maxSlot).contains(slot) else { return nil }
        return slots.first(where: { $0.value == slot })?.key
    }
}

/// Slice MC-2 — Maccy's keyboard table, resolved from a key and its modifiers. Pure so the flyout only has to map
/// `NSEvent` once and dispatch the command it gets back.
enum MaccyKeyAction: Equatable, Sendable {
    case copy                 // ⏎
    case paste                // ⌥⏎
    case pastePlain           // ⌥⇧⏎
    case togglePin            // ⌥P
    case delete               // ⌥⌫
    case clearUnpinned        // ⌥⌘⌫
    case clearAll             // ⇧⌥⌘⌫
    case selectPinSlot(Int)   // ⌘1…⌘9

    struct Modifiers: OptionSet, Sendable, Equatable {
        let rawValue: Int
        static let option = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let command = Modifiers(rawValue: 1 << 2)
    }

    /// `key` is the event's `charactersIgnoringModifiers`; `"return"` and `"delete"` are accepted as names too, so a
    /// test or a menu item can call this without building an `NSEvent`.
    static func action(key: String, modifiers: Modifiers) -> MaccyKeyAction? {
        let lowered = key.lowercased()
        switch lowered {
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            guard modifiers == .command, let slot = Int(lowered) else { return nil }
            return .selectPinSlot(slot)
        case "return", "\r", "\n", "enter":
            if modifiers == [.option, .shift] { return .pastePlain }
            if modifiers == .option { return .paste }
            return modifiers.isEmpty ? .copy : nil
        case "p":
            return modifiers == .option ? .togglePin : nil
        case "delete", "backspace", "\u{8}", "\u{7f}":
            if modifiers == [.option, .command] { return .clearUnpinned }
            if modifiers == [.shift, .option, .command] { return .clearAll }
            return modifiers == .option ? .delete : nil
        default:
            return nil
        }
    }
}
