import Foundation

/// Atomic JSON persistence for the Desktop Quick Capture inbox (`desktop-capture.json`).
@MainActor
final class DesktopQuickCaptureStore: ObservableObject {
    static let shared = DesktopQuickCaptureStore()

    @Published private(set) var log: DesktopCaptureLog
    private let url: URL

    nonisolated static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("KatiKati/desktop-capture.json", isDirectory: false)
    }

    init(url: URL = DesktopQuickCaptureStore.defaultURL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(DesktopCaptureLog.self, from: data) {
            log = decoded
        } else {
            log = DesktopCaptureLog()
        }
    }

    func add(_ text: String) { mutate { $0.add(text) } }
    func delete(_ id: UUID) { mutate { $0.delete(id) } }

    private func mutate(_ change: (inout DesktopCaptureLog) -> Void) {
        var next = log
        change(&next)
        guard next != log else { return }
        log = next
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
        } catch {
            NSLog("DesktopQuickCaptureStore save failed: \(error.localizedDescription)")
        }
    }
}
