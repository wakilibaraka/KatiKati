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

    init(id: UUID, directory: String?) {
        self.id = id
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 380))
        super.init()
        view.processDelegate = self
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(executable: shell, args: ["-l"], environment: nil, execName: nil,
                          currentDirectory: directory ?? NSHomeDirectory())
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
