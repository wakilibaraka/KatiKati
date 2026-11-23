import Foundation

/// Phase 29b: the short-keyword layer. A **bare word** is a macro (runs immediately); a **word followed
/// by a space** is a mode (takes the rest as its argument). Layered above the single-char prefixes.
/// Learned from Snap (keyword+argument actions) and Cling/oil-find (short filter words).
enum CommandBarMode: CaseIterable, Sendable {
    case file, image, clipboard, emoji, bookmark, event, kill, forceQuit, killProcess, shortcut, apps
    /// Port plan #3: the frontmost app's menu items (`AppMenuSearchReader` + `MenuSearch`).
    case menu
    /// Port plan #4: bar profiles. `profile work` applies Work; `profile save work` stores the bar as Work.
    case profile
    /// `define <word>` opens the dictionary panel on that word.
    case define
    /// Homebrew search mode (`bs <term>` or `brew <term>`).
    case brewSearch

    var keywords: [String] {
        switch self {
        case .file: return ["f", "file"]
        case .image: return ["img", "image"]
        case .clipboard: return ["clip", "clipboard", "c"]
        case .emoji: return ["emoji", "em", "emo"]
        case .bookmark: return ["bm", "bookmark", "b"]
        case .event: return ["ev", "event"]
        case .kill: return ["kill"]
        case .forceQuit: return ["fq"]
        case .killProcess: return ["kp"]
        case .shortcut: return ["sc", "shortcut"]
        case .apps: return ["app"]
        case .menu: return ["m", "menu"]
        case .profile: return ["profile"]
        case .define: return ["define", "def"]
        case .brewSearch: return ["brew", "bs"]
        }
    }

    var displayName: String {
        switch self {
        case .file: return "Files"; case .image: return "Images"; case .clipboard: return "Clipboard"
        case .emoji: return "Emoji"; case .bookmark: return "Bookmarks"; case .event: return "Calendar"
        case .kill: return "Quit Apps"; case .forceQuit: return "Force Quit"; case .killProcess: return "Kill Process"
        case .shortcut: return "Shortcuts"; case .apps: return "Applications"; case .menu: return "Menu Items"
        case .profile: return "Bar Profiles"; case .define: return "Dictionary"; case .brewSearch: return "Homebrew"
        }
    }

    var symbol: String {
        switch self {
        case .file: return "doc"; case .image: return "photo"; case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"; case .bookmark: return "bookmark"; case .event: return "calendar"
        case .kill: return "xmark.circle"; case .forceQuit: return "bolt.slash"; case .killProcess: return "cpu"
        case .shortcut: return "bolt.fill"; case .apps: return "app.dashed"; case .menu: return "filemenu.and.selection"
        case .profile: return "rectangle.3.group"; case .define: return "character.book.closed"; case .brewSearch: return "shippingbox"
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
    case pauseKeyboard, cleanKeyboard, teleprompter
    case snapLeft, snapRight, snapTop, snapBottom, snapMaximize, snapCenter, snapNextDisplay
    case tileFloat, tileRetile

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
        case .pauseKeyboard: return ["pause"]
        case .cleanKeyboard: return ["clean"]
        case .teleprompter: return ["prompter", "tp"]
        case .snapLeft: return ["left", "snapleft", "lefthalf"]
        case .snapRight: return ["right", "snapright", "righthalf"]
        case .snapTop: return ["top", "snaptop", "tophalf"]
        case .snapBottom: return ["bottom", "snapbottom", "bottomhalf"]
        case .snapMaximize: return ["maximize", "fullscreen", "max"]
        case .snapCenter: return ["center", "middle"]
        case .snapNextDisplay: return ["nextdisplay", "display", "monitor"]
        case .tileFloat: return ["tile float", "float", "tilefloat"]
        case .tileRetile: return ["tile retile", "retile", "tileretile"]
        }
    }

    var title: String {
        switch self {
        case .ocr: return "Screen OCR"
        case .shortcutsApp: return "Shortcuts"
        case .terminal: return "Terminal"
        case .screensaver: return "Screen Saver"
        case .lock: return "Lock Screen"
        case .sleep: return "Sleep"
        case .restart: return "Restart Mac"
        case .shutdown: return "Shut Down"
        case .logout: return "Log Out"
        case .darkMode: return "Toggle Dark Mode"
        case .keepAwake: return "Stay Awake"
        case .muteMic: return "Mute Microphone"
        case .nightShift: return "Toggle Night Shift"
        case .trueTone: return "Toggle True Tone"
        case .wifi: return "Toggle Wi-Fi"
        case .bluetooth: return "Toggle Bluetooth"
        case .menuBar: return "Toggle Menu Bar"
        case .emptyTrash: return "Empty Trash"
        case .eject: return "Eject All Disks"
        case .hideDesktopIcons: return "Hide Desktop Icons"
        case .dockAutoHide: return "Toggle Dock Auto-Hide"
        case .relaunchFinder: return "Relaunch Finder"
        case .play: return "Play / Pause"
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        case .pauseKeyboard: return "Pause Keyboard"
        case .cleanKeyboard: return "Clean Keyboard Mode"
        case .teleprompter: return "Teleprompter"
        case .snapLeft: return "Left Half"
        case .snapRight: return "Right Half"
        case .snapTop: return "Top Half"
        case .snapBottom: return "Bottom Half"
        case .snapMaximize: return "Maximize Window"
        case .snapCenter: return "Center Window"
        case .snapNextDisplay: return "Move to Next Display"
        case .tileFloat: return "Float Focused Window"
        case .tileRetile: return "Retile All Windows"
        }
    }

    var subtitle: String {
        switch self {
        case .snapLeft, .snapRight, .snapTop, .snapBottom, .snapMaximize, .snapCenter:
            return "Snap Frontmost Window"
        case .snapNextDisplay, .tileFloat, .tileRetile:
            return "Window Management"
        case .ocr, .shortcutsApp, .terminal, .teleprompter:
            return "Utility"
        case .play, .next, .previous:
            return "Media Control"
        case .pauseKeyboard, .cleanKeyboard:
            return "KeyGuard"
        default:
            return "System Action"
        }
    }

    var snapPosition: SnapPosition? {
        switch self {
        case .snapLeft: return .leftHalf
        case .snapRight: return .rightHalf
        case .snapTop: return .topHalf
        case .snapBottom: return .bottomHalf
        case .snapMaximize: return .maximize
        case .snapCenter: return .center
        default: return nil
        }
    }

    static func matching(_ query: String) -> [BarMacro] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return allCases.filter { macro in
            macro.keywords.contains { $0.hasPrefix(q) || $0.contains(q) } ||
            macro.title.lowercased().contains(q)
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
        case .pauseKeyboard: return "pause.circle"
        case .cleanKeyboard: return "sparkles"
        case .teleprompter: return "text.alignleft"
        case .snapLeft: return "rectangle.lefthalf.inset.filled"
        case .snapRight: return "rectangle.righthalf.inset.filled"
        case .snapTop: return "rectangle.tophalf.inset.filled"
        case .snapBottom: return "rectangle.bottomhalf.inset.filled"
        case .snapMaximize: return "arrow.up.left.and.arrow.down.right"
        case .snapCenter: return "rectangle.center.inset.filled"
        case .snapNextDisplay: return "display.2"
        case .tileFloat: return "macwindow.on.rectangle"
        case .tileRetile: return "square.grid.2x2"
        default: return "bolt"
        }
    }
}

enum CommandKeyword {
    enum Parsed: Equatable, Sendable {
        case mode(CommandBarMode, String)
        case macro(BarMacro)
    }

    /// A bare macro word, or `word ` + argument. Trims only leading whitespace before checking
    /// for the space delimiter so "clip ", "emoji ", "bm ", etc. enter mode with an empty argument.
    static func parse(_ query: String) -> Parsed? {
        let leadingTrimmed = query.drop(while: { $0 == " " || $0 == "\t" })
        guard !leadingTrimmed.isEmpty else { return nil }
        if let space = leadingTrimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            let word = String(leadingTrimmed[leadingTrimmed.startIndex..<space]).lowercased()
            let argument = String(leadingTrimmed[leadingTrimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            if let mode = CommandBarMode.allCases.first(where: { $0.keywords.contains(word) }) {
                return .mode(mode, argument)
            }
        }
        let lower = leadingTrimmed.trimmingCharacters(in: .whitespaces).lowercased()
        if let macro = BarMacro.allCases.first(where: { $0.keywords.contains(lower) }) {
            return .macro(macro)
        }
        return nil
    }
}

/// Phase 30d: a Trash operation, offered as rows when the query is `trash`.
enum TrashAction: String, CaseIterable, Sendable {
    case open, empty, emptyWithoutConfirmation

    var needsConfirm: Bool { self == .empty }
    var symbol: String { self == .open ? "trash" : "trash.slash" }
}
