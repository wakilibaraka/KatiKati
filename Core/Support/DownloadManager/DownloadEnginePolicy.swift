import Foundation

/// SD-4: the download engine's policy — how many connections a segmented transfer may open, when a stream
/// counts as stalled, and where a paused transfer can be picked up again.
///
/// Pure values with clamping: the service reads one object, and `DownloadEnginePolicyTests` pins every
/// boundary (1…32 connections, stall window, reconnect budget, resume round-trip).
struct DownloadEnginePolicy: Equatable, Sendable {
    static let defaultsKey = "com.katikati.downloads.engine.v1"
    static let connectionsRange: ClosedRange<Int> = 1...32

    var connections: Int
    var stallWindow: TimeInterval
    var stallRateFraction: Double
    var reconnectAttempts: Int

    /// Eight connections is the IDM-class default: enough to fill a fast line without tripping servers that
    /// throttle aggressive clients (the owner can set 1…32 once SD-8 owns the Settings row).
    static let standard = DownloadEnginePolicy(connections: 8)

    init(connections: Int, stallWindow: TimeInterval = 8, stallRateFraction: Double = 0.12,
         reconnectAttempts: Int = 2) {
        self.connections = min(max(connections, Self.connectionsRange.lowerBound), Self.connectionsRange.upperBound)
        self.stallWindow = max(2, stallWindow)
        self.stallRateFraction = min(max(0.01, stallRateFraction), 0.9)
        self.reconnectAttempts = max(0, min(reconnectAttempts, 8))
    }

    static func stored(in defaults: UserDefaults = .standard) -> DownloadEnginePolicy {
        let raw = defaults.object(forKey: defaultsKey + ".connections") as? Int
        return DownloadEnginePolicy(connections: raw ?? standard.connections)
    }

    /// How many segments this policy actually allows for a body: never more than the byte budget can pay for.
    func segmentCount(forContentLength length: Int64?,
                      minimumSegmentBytes: Int64 = DownloadSegmentPlanner.minimumSegmentBytes) -> Int {
        guard let length, length > 0 else { return 1 }
        let capacity = Int(max(1, length / max(1, minimumSegmentBytes)))
        return max(1, min(connections, capacity))
    }
}

/// SD-4: statistical stall detection. A transfer is stalled when its rate over the last window falls below a
/// fraction of the best rate it has shown — the connection went quiet, rather than merely slow.
struct DownloadStallDetector: Sendable {
    private struct Sample: Sendable {
        let at: Date
        let bytes: Int64
    }

    private var samples: [Sample] = []
    private let window: TimeInterval
    private let rateFraction: Double
    private let reconnectBudget: Int
    private(set) var reconnects = 0

    init(policy: DownloadEnginePolicy) {
        window = policy.stallWindow
        rateFraction = policy.stallRateFraction
        reconnectBudget = policy.reconnectAttempts
    }

    mutating func record(bytes: Int64, at now: Date = Date()) {
        samples.append(Sample(at: now, bytes: bytes))
        samples.removeAll { now.timeIntervalSince($0.at) > window * 4 }
    }

    /// Bytes per second since the window opened: the newest sample against the last one at or before the
    /// cutoff. A transfer that has recorded nothing for a whole window has a baseline at its own newest
    /// sample, so its recent rate is 0 rather than "unknown" — which is exactly what a stall looks like.
    func recentRate(now: Date = Date()) -> Double? {
        guard let newest = samples.last else { return nil }
        // A whole window with nothing recorded is the stall this exists to catch: the rate is 0, not unknown.
        if now.timeIntervalSince(newest.at) >= window { return 0 }
        let cutoff = now.addingTimeInterval(-window)
        let baseline = samples.last { $0.at <= cutoff } ?? samples[0]
        let span = newest.at.timeIntervalSince(baseline.at)
        guard span > 0 else { return nil }
        return Double(max(0, newest.bytes - baseline.bytes)) / span
    }

    /// The best rate any consecutive pair of samples showed, which is what "quiet" is measured against.
    func peakRate() -> Double? {
        var best: Double?
        for (previous, next) in zip(samples, samples.dropFirst()) {
            let span = next.at.timeIntervalSince(previous.at)
            guard span > 0 else { continue }
            let rate = Double(max(0, next.bytes - previous.bytes)) / span
            if rate > (best ?? 0) { best = rate }
        }
        return best
    }

    func isStalled(now: Date = Date()) -> Bool {
        guard let peak = peakRate(), peak > 0, let recent = recentRate(now: now) else { return false }
        return recent < peak * rateFraction
    }

    var canReconnect: Bool { reconnects < reconnectBudget }

    /// Records one reconnect; false when the budget is spent and the transfer should fail visibly instead.
    mutating func noteReconnect() -> Bool {
        guard canReconnect else { return false }
        reconnects += 1
        samples.removeAll()
        return true
    }
}

/// SD-4: what a paused transfer needs to pick up where it stopped, including across an app relaunch.
struct DownloadResumeRecord: Codable, Equatable, Sendable {
    let source: String
    let destination: String
    let totalBytes: Int64
    let isMultiSegment: Bool
    var completed: [Int: Int64]

    static func directory(applicationSupport: URL? = nil) -> URL {
        let base = applicationSupport ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                                 in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("KatiKati/downloads", isDirectory: true)
    }

    func write(id: UUID, in directory: URL = DownloadResumeRecord.directory()) {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        } catch {
            // A resume record is an optimisation: losing it costs bytes, never correctness.
        }
    }

    static func read(id: UUID, in directory: URL = DownloadResumeRecord.directory()) -> DownloadResumeRecord? {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DownloadResumeRecord.self, from: data)
    }

    static func remove(id: UUID, in directory: URL = DownloadResumeRecord.directory()) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString + ".json"))
    }
}

/// SD-4: smart folders — a finished download lands where the owner expects it, without a dialog per file.
enum DownloadDestinationPolicy {
    static let videoExtensions: Set<String> = ["mp4", "mov", "mkv", "avi", "webm", "m4v", "mpg", "mpeg"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aiff", "ogg", "opus"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "avif"]

    /// The standard media folder name for an extension, or nil when the Downloads folder is right.
    static func folderName(for fileName: String) -> String? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        if videoExtensions.contains(ext) { return "Movies" }
        if audioExtensions.contains(ext) { return "Music" }
        if imageExtensions.contains(ext) { return "Pictures" }
        return nil
    }
}
