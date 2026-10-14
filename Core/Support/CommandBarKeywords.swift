import Foundation

/// Phase 29b: the short-keyword layer. A **bare word** is a macro (runs immediately); a **word followed
/// by a space** is a mode (takes the rest as its argument). Layered above the single-char prefixes.
/// Learned from Snap (keyword+argument actions) and Cling/oil-find (short filter words).
enum CommandBarMode: CaseIterable, Sendable {
    case file, image, clipboard, emoji, bookmark, event, kill, forceQuit, killProcess, shortcut, apps

    var keywords: [String] {
        switch self {
        case .file: return ["f", "file"]
        case .image: return ["img", "image"]
        case .clipboard: return ["clip", "clipboard"]
        case .emoji: return ["emoji", "em"]
        case .bookmark: return ["bm", "bookmark"]
        case .event: return ["ev", "event"]
        case .kill: return ["kill"]
        case .forceQuit: return ["fq"]
        case .killProcess: return ["kp"]
        case .shortcut: return ["sc", "shortcut"]
        case .apps: return ["app"]
        }
    }
}

/// A native macOS action run straight from the bar. Most delegate to `QuickToggleEngine`; the rest are
/// handled by `BarActionService` (media keys, power, OCR, opening apps).
enum BarMacro: CaseIterable, Sendable {
    case ocr, shortcutsApp, terminal, screensaver, lock, sleep, restart, shutdown, logout
    case darkMode, keepAwake, muteMic, nightShift, trueTone, wifi, bluetooth, menuBar
    case emptyTrash, eject, hideDesktopIcons, dockAutoHide, relaunchFinder
    case play, next, previous

    var keywords: [String] {
        switch self {
        case .ocr: return ["ocr"]
        case .shortcutsApp: return ["cs"]
        case .terminal: return ["term"]
        case .screensaver: return ["ss", "screensaver"]
        case .lock: return ["lock"]
        case .sleep: return ["sleep"]
        case .restart: return ["restart"]
        case .shutdown: return ["shutdown"]
        case .logout: return ["logout"]
        case .darkMode: return ["dark"]
        case .keepAwake: return ["awake"]
        case .muteMic: return ["mute"]
        case .nightShift: return ["night"]
        case .trueTone: return ["truetone"]
        case .wifi: return ["wifi"]
        case .bluetooth: return ["bt"]
        case .menuBar: return ["menubar"]
        case .emptyTrash: return ["emptytrash"]
        case .eject: return ["eject"]
        case .hideDesktopIcons: return ["hideicons"]
        case .dockAutoHide: return ["dock"]
        case .relaunchFinder: return ["finder"]
        case .play: return ["play"]
        case .next: return ["next"]
        case .previous: return ["prev"]
        }
    }

    var keyword: String { keywords[0] }

    /// Toggle/action-backed macros go through `QuickToggleEngine`.
    var quickToggle: QuickToggleID? {
        switch self {
        case .screensaver: return .screenSaver
        case .lock: return .lockScreen
        case .darkMode: return .darkMode
        case .keepAwake: return .keepAwake
        case .muteMic: return .muteMic
        case .nightShift: return .nightShift
        case .trueTone: return .trueTone
        case .wifi: return .wifi
        case .bluetooth: return .bluetooth
        case .emptyTrash: return .emptyTrash
        case .eject: return .ejectDisks
        case .hideDesktopIcons: return .hideDesktopIcons
        case .dockAutoHide: return .dockAutoHide
        case .relaunchFinder: return .relaunchFinder
        default: return nil
        }
    }

    var needsConfirm: Bool {
        if let id = quickToggle { return id.needsConfirm }
        return self == .restart || self == .shutdown || self == .logout
    }

    var symbol: String {
        if let id = quickToggle { return id.symbolName }
        switch self {
        case .ocr: return "text.viewfinder"
        case .shortcutsApp: return "bolt.fill"
        case .terminal: return "terminal"
        case .sleep: return "moon.zzz"
        case .restart: return "arrow.clockwise"
        case .shutdown: return "power"
        case .logout: return "rectangle.portrait.and.arrow.right"
        case .menuBar: return "menubar.rectangle"
        case .play: return "play.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        default: return "bolt"
        }
    }
}

enum CommandKeyword {
    enum Parsed: Equatable, Sendable {
        case mode(CommandBarMode, String)
        case macro(BarMacro)
    }

    /// A bare macro word, or `word ` + argument. Returns nil for everything else (the single-char
    /// prefixes and plain search carry on).
    static func parse(_ query: String) -> Parsed? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if let macro = BarMacro.allCases.first(where: { $0.keywords.contains(lower) }) { return .macro(macro) }
        guard let space = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
        let word = String(trimmed[trimmed.startIndex..<space]).lowercased()
        let argument = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        if let mode = CommandBarMode.allCases.first(where: { $0.keywords.contains(word) }) { return .mode(mode, argument) }
        return nil
    }
}

/// Phase 30d: a Trash operation, offered as rows when the query is `trash`.
enum TrashAction: String, CaseIterable, Sendable {
    case open, empty, emptyWithoutConfirmation

    var needsConfirm: Bool { self == .empty }
    var symbol: String { self == .open ? "trash" : "trash.slash" }
}
