import Foundation

struct DownloadSegment: Equatable, Sendable {
    let index: Int
    let start: Int64
    let end: Int64
    var completedBytes: Int64 = 0
    var length: Int64 { end - start + 1 }
    var remainingBytes: Int64 { max(0, length - completedBytes) }
    var rangeHeader: String { "bytes=\(start)-\(end)" }
}

struct DownloadSegmentPlan: Equatable, Sendable {
    let segments: [DownloadSegment]
    let isMultiSegment: Bool
    var totalBytes: Int64 { segments.reduce(0) { $0 + $1.length } }
    var completedBytes: Int64 { segments.reduce(0) { $0 + $1.completedBytes } }
    var remainingBytes: Int64 { max(0, totalBytes - completedBytes) }
    func speedAndETA(bytesPerSecond: Int64, now: Date = Date()) -> (speed: Int64, eta: Int64?) {
        let speed = max(0, bytesPerSecond)
        guard speed > 0 else { return (0, nil) }
        return (speed, max(0, remainingBytes / speed))
    }
}

enum DownloadSegmentPlanner {
    static let defaultSegmentCount = 4
    static let minimumSegmentBytes: Int64 = 1_048_576

    static func plan(contentLength: Int64?, acceptRanges: Bool, segmentCount: Int = defaultSegmentCount,
                     minimumSegmentBytes: Int64 = DownloadSegmentPlanner.minimumSegmentBytes) -> DownloadSegmentPlan {
        guard let length = contentLength, length > 0, acceptRanges, segmentCount > 1,
              length >= minimumSegmentBytes * 2 else {
            let length = contentLength ?? 0
            return DownloadSegmentPlan(
                segments: length > 0 ? [DownloadSegment(index: 0, start: 0, end: length - 1)] : [],
                isMultiSegment: false
            )
        }
        let maximumSegments = max(1, length / max(1, minimumSegmentBytes))
        // SD-4: the engine's ceiling is 32 connections (DownloadEnginePolicy), not the old 16.
        let count = min(max(1, segmentCount), Int(maximumSegments), DownloadEnginePolicy.connectionsRange.upperBound)
        guard count > 1 else {
            return DownloadSegmentPlan(segments: [DownloadSegment(index: 0, start: 0, end: length - 1)], isMultiSegment: false)
        }
        let base = length / Int64(count)
        let remainder = length % Int64(count)
        var cursor: Int64 = 0
        var segments: [DownloadSegment] = []
        for index in 0..<count {
            let extra = Int64(index < Int(remainder) ? 1 : 0)
            let end = cursor + base + extra - 1
            segments.append(DownloadSegment(index: index, start: cursor, end: end))
            cursor = end + 1
        }
        return DownloadSegmentPlan(segments: segments, isMultiSegment: true)
    }
}

// MARK: - Download Types & State

public enum DownloadType: String, Codable, CaseIterable, Sendable {
    case browser    // Tracked in-progress download from Safari, Chrome, Firefox, Arc, etc.
    case directUrl  // Direct HTTP/HTTPS download initiated in KatiKati
    case torrent    // BitTorrent / Magnet link download

    public var iconName: String {
        switch self {
        case .browser: return "globe"
        case .directUrl: return "arrow.down.circle.fill"
        case .torrent: return "point.3.connected.trianglepath.dotted"
        }
    }
}

public enum DownloadItemState: Equatable, Sendable {
    case initializing
    case active
    case paused
    case completed
    case failed(String)

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }

    public var displayText: String {
        switch self {
        case .initializing: return "CONNECTING"
        case .active: return "DOWNLOADING"
        case .paused: return "PAUSED"
        case .completed: return "COMPLETED"
        case .failed: return "FAILED"
        }
    }
}

// MARK: - DownloadItem

public struct DownloadItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var type: DownloadType
    public var state: DownloadItemState
    public var sourceURL: String?
    public var destinationURL: URL?
    public var infoHash: String?

    public var bytesDownloaded: Int64
    public var totalBytes: Int64
    public var downloadSpeedBps: Int64
    public var uploadSpeedBps: Int64

    public var seeders: Int
    public var peers: Int
    public var etaSeconds: Int?
    public var addedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        type: DownloadType,
        state: DownloadItemState = .active,
        sourceURL: String? = nil,
        destinationURL: URL? = nil,
        infoHash: String? = nil,
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 0,
        downloadSpeedBps: Int64 = 0,
        uploadSpeedBps: Int64 = 0,
        seeders: Int = 0,
        peers: Int = 0,
        etaSeconds: Int? = nil,
        addedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.state = state
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.infoHash = infoHash
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.downloadSpeedBps = downloadSpeedBps
        self.uploadSpeedBps = uploadSpeedBps
        self.seeders = seeders
        self.peers = peers
        self.etaSeconds = etaSeconds
        self.addedAt = addedAt
        self.completedAt = completedAt
    }

    /// Progress fraction between 0.0 and 1.0
    public var fraction: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(bytesDownloaded) / Double(totalBytes)))
    }

    /// Formatted transfer speed (e.g. "8.4 MB/s")
    public var formattedSpeed: String {
        guard state == .active, downloadSpeedBps > 0 else { return "0 B/s" }
        return Self.formatBytes(downloadSpeedBps) + "/s"
    }

    /// Formatted progress sizes (e.g. "412 MB / 1.2 GB" or "412 MB")
    public var formattedSizeProgress: String {
        let downloaded = Self.formatBytes(bytesDownloaded)
        if totalBytes > 0 {
            let total = Self.formatBytes(totalBytes)
            return "\(downloaded) / \(total)"
        }
        return downloaded
    }

    /// Formatted ETA string (e.g. "1m 24s", "42s", or "Estimating…")
    public var formattedETA: String {
        guard state == .active else { return "—" }
        guard let eta = etaSeconds, eta > 0 else { return "Calculating…" }
        if eta < 60 {
            return "\(eta)s"
        } else if eta < 3600 {
            let m = eta / 60
            let s = eta % 60
            return "\(m)m \(s)s"
        } else {
            let h = eta / 3600
            let m = (eta % 3600) / 60
            return "\(h)h \(m)m"
        }
    }

    /// Upload/download ratio for torrents
    public var seedRatio: Double {
        guard bytesDownloaded > 0 else { return 0.0 }
        return Double(bytesDownloaded) > 0 ? (Double(uploadSpeedBps * 10) / Double(bytesDownloaded)) : 0.0
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024 {
            return "\(bytes) B"
        } else if b < 1024 * 1024 {
            return String(format: "%.1f KB", b / 1024)
        } else if b < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", b / (1024 * 1024))
        } else {
            return String(format: "%.2f GB", b / (1024 * 1024 * 1024))
        }
    }
}

// MARK: - Magnet URI Parser

public enum MagnetURIParser {
    public struct ParsedMagnet: Equatable {
        public let displayName: String
        public let infoHash: String
        public let exactLength: Int64?
        public let trackers: [String]

        public init(displayName: String, infoHash: String, exactLength: Int64? = nil, trackers: [String] = []) {
            self.displayName = displayName
            self.infoHash = infoHash
            self.exactLength = exactLength
            self.trackers = trackers
        }
    }

    public static func parse(_ uri: String) -> ParsedMagnet? {
        guard uri.lowercased().hasPrefix("magnet:?") else { return nil }
        let queryString = String(uri.dropFirst("magnet:?".count))
        let pairs = queryString.components(separatedBy: "&")

        var displayName: String?
        var infoHash: String?
        var exactLength: Int64?
        var trackers: [String] = []

        for pair in pairs {
            let parts = pair.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key = parts[0].lowercased()
            let rawVal = parts[1...].joined(separator: "=")
            let val = rawVal.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawVal

            switch key {
            case "dn":
                displayName = val
            case "xt":
                if val.lowercased().hasPrefix("urn:btih:") {
                    infoHash = String(val.dropFirst("urn:btih:".count)).uppercased()
                } else if val.lowercased().hasPrefix("urn:btmh:") {
                    infoHash = String(val.dropFirst("urn:btmh:".count)).uppercased()
                } else {
                    infoHash = val.uppercased()
                }
            case "xl":
                exactLength = Int64(val)
            case "tr":
                trackers.append(val)
            default:
                break
            }
        }

        guard let hash = infoHash, !hash.isEmpty else { return nil }
        let title = displayName ?? "Torrent-\(hash.prefix(8))"
        return ParsedMagnet(displayName: title, infoHash: hash, exactLength: exactLength, trackers: trackers)
    }
}
