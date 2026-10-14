import AppKit

/// Phase 29b: runs a `BarMacro` from the command bar. Toggle/action macros delegate to
/// `QuickToggleEngine`; the rest are handled here (media keys, power, OCR, opening apps).
@MainActor
enum BarActionService {
    private static let nowPlaying = NowPlayingService()
    private static let capture = CaptureController()

    static func run(_ macro: BarMacro) {
        if let id = macro.quickToggle {
            QuickToggleEngine.shared.perform(id)
            return
        }
        switch macro {
        case .ocr:
            runOCR()
        case .shortcutsApp:
            open("/System/Applications/Shortcuts.app")
        case .terminal:
            open("/System/Applications/Utilities/Terminal.app")
        case .sleep:
            shell("/usr/bin/pmset", ["sleepnow"])
        case .restart:
            osascript("tell application \"System Events\" to restart")
        case .shutdown:
            osascript("tell application \"System Events\" to shut down")
        case .logout:
            osascript("tell application \"System Events\" to log out")
        case .menuBar:
            toggleMenuBarAutoHide()
        case .play:
            nowPlaying.togglePlayPause()
        case .next:
            nowPlaying.nextTrack()
        case .previous:
            nowPlaying.previousTrack()
        default:
            break
        }
    }

    /// Region capture → OCR → recognised text onto the clipboard (nothing is kept).
    private static func runOCR() {
        capture.start { [capture] in
            if case let .done(text, _) = capture.state, !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    private static func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private static func shell(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }

    private static func osascript(_ source: String) {
        shell("/usr/bin/osascript", ["-e", source])
    }

    /// Toggle the menu bar's auto-hide (private `_HIHideMenuBar`), then restart SystemUIServer so it takes.
    private static func toggleMenuBarAutoHide() {
        let current = UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
        shell("/usr/bin/defaults", ["write", "NSGlobalDomain", "_HIHideMenuBar", "-bool", current ? "false" : "true"])
        shell("/usr/bin/killall", ["SystemUIServer"])
    }
}
