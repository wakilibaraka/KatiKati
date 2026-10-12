import AppKit

/// Phase 8e — rewrites a copied link without its tracking parameters (`URLCleaner` decides). Opt-in,
/// default OFF: it edits the clipboard, so it never runs unless asked. One 0.7 s `changeCount` poll that
/// exists only while enabled; concealed/transient copies (password managers) are never read.
@MainActor
final class LinkCleanerService {
    private let pasteboard: NSPasteboard
    private var lastChange: Int
    private var timer: Timer?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChange = pasteboard.changeCount
    }

    func setEnabled(_ on: Bool) {
        timer?.invalidate(); timer = nil
        guard on else { return }
        lastChange = pasteboard.changeCount   // what was copied before switching on is not ours to rewrite
        let t = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.3
        timer = t
    }

    private func poll() {
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard ClipboardHistory.shouldRecord(types: types),
              let text = pasteboard.string(forType: .string),
              let cleaned = URLCleaner.clean(text) else { return }
        pasteboard.clearContents()
        pasteboard.setString(cleaned, forType: .string)
        lastChange = pasteboard.changeCount   // our own write is not a new copy
    }

    deinit { timer?.invalidate() }
}
