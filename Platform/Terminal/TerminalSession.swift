import AppKit
import SwiftTerm

/// One shell: a SwiftTerm view running `$SHELL -l`. Reports title/cwd/exit to its owner; sessions outlive the
/// panel being hidden and die with the app (or when their tab closes).
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let id: UUID
    let view: LocalProcessTerminalView
    var onTitle: ((UUID, String) -> Void)?
    var onDirectory: ((UUID, String) -> Void)?
    var onExit: ((UUID) -> Void)?

    init(id: UUID, directory: String?, theme: TerminalThemePreset = .katikatiDark) {
        self.id = id
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 380))
        super.init()
        view.processDelegate = self
        applyTheme(theme)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(executable: shell, args: ["-l"], environment: nil, execName: nil,
                          currentDirectory: directory ?? NSHomeDirectory())
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        view.send(data: ArraySlice(text.utf8))
    }

    func applyTheme(_ theme: TerminalThemePreset) {
        let bg = theme.backgroundRGB
        let fg = theme.foregroundRGB
        view.nativeBackgroundColor = NSColor(calibratedRed: bg.r, green: bg.g, blue: bg.b, alpha: 1)
        view.nativeForegroundColor = NSColor(calibratedRed: fg.r, green: fg.g, blue: fg.b, alpha: 1)
    }

    func readBufferText() -> String {
        let data = view.getTerminal().getBufferAsData(kind: .active, encoding: .utf8)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func terminate() { view.terminate() }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in self.onTitle?(self.id, title) }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        Task { @MainActor in self.onDirectory?(self.id, directory) }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in self.onExit?(self.id) }
    }
}
