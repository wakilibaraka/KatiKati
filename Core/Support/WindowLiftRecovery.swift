import Foundation

/// Crash-recovery record for lifted windows (5c). The live lift sessions only exist in memory, so a
/// `kill -9` / crash leaves windows displaced with nobody remembering their native frame. The
/// controller mirrors its pending restorations here; the next launch replays them through the normal
/// restore path (which re-checks process start time, window liveness and that the window is still at
/// the lifted frame before writing anything).
struct WindowLiftRecoveryRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    init(_ rect: CGRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y),
                  width: Double(rect.size.width), height: Double(rect.size.height))
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct WindowLiftRecoveryEntry: Codable, Equatable {
    var pid: Int32
    var windowID: UInt32
    var startSeconds: Int
    var startMicroseconds: Int32
    var nativeAppKit: WindowLiftRecoveryRect
    var targetAppKit: WindowLiftRecoveryRect
    var nativeQuartz: WindowLiftRecoveryRect
    var targetQuartz: WindowLiftRecoveryRect
    var primaryScreenHeight: Double
}

struct WindowLiftRecoverySnapshot: Codable, Equatable {
    static let currentVersion = 1
    var version: Int = WindowLiftRecoverySnapshot.currentVersion
    var entries: [WindowLiftRecoveryEntry]

    static func decode(_ data: Data) -> WindowLiftRecoverySnapshot? {
        guard let snapshot = try? JSONDecoder().decode(WindowLiftRecoverySnapshot.self, from: data),
              snapshot.version == currentVersion else { return nil }
        return snapshot
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
}

/// Atomic one-file store. Empty snapshots delete the file so a clean quit leaves nothing behind.
struct WindowLiftRecoveryStore {
    let url: URL

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleID = Bundle.main.bundleIdentifier ?? "com.caye.macosdockcc.v2"
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("window-lift-recovery.json")
    }

    func save(_ entries: [WindowLiftRecoveryEntry]) {
        guard !entries.isEmpty else { clear(); return }
        guard let data = WindowLiftRecoverySnapshot(entries: entries).encoded() else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    func load() -> [WindowLiftRecoveryEntry] {
        guard let data = try? Data(contentsOf: url),
              let snapshot = WindowLiftRecoverySnapshot.decode(data) else { return [] }
        return snapshot.entries
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
