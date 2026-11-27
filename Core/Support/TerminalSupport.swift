import CoreGraphics
import Foundation

/// Color theme presets for the floating Terminal panel.
public enum TerminalThemePreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case katikatiDark = "katikatiDark"
    case midnightOcean = "midnightOcean"
    case solarizedDark = "solarizedDark"
    case paperLight = "paperLight"

    public var id: String { rawValue }
    public static let storageKey = "com.katikati.terminal.theme"

    public struct RGB: Equatable, Sendable {
        public let r: Double
        public let g: Double
        public let b: Double
    }

    public var title: String {
        switch self {
        case .katikatiDark: return "KatiKati Dark"
        case .midnightOcean: return "Midnight Ocean"
        case .solarizedDark: return "Solarized Dark"
        case .paperLight: return "Paper Light"
        }
    }

    public var backgroundRGB: RGB {
        switch self {
        case .katikatiDark: return RGB(r: 0.09, g: 0.10, b: 0.12)
        case .midnightOcean: return RGB(r: 0.05, g: 0.11, b: 0.19)
        case .solarizedDark: return RGB(r: 0.00, g: 0.17, b: 0.21)
        case .paperLight: return RGB(r: 0.96, g: 0.95, b: 0.92)
        }
    }

    public var foregroundRGB: RGB {
        switch self {
        case .katikatiDark: return RGB(r: 0.93, g: 0.94, b: 0.96)
        case .midnightOcean: return RGB(r: 0.86, g: 0.93, b: 0.99)
        case .solarizedDark: return RGB(r: 0.58, g: 0.63, b: 0.63)
        case .paperLight: return RGB(r: 0.12, g: 0.13, b: 0.16)
        }
    }

    public var cursorRGB: RGB {
        switch self {
        case .katikatiDark: return RGB(r: 0.35, g: 0.78, b: 0.98)
        case .midnightOcean: return RGB(r: 0.42, g: 0.89, b: 0.76)
        case .solarizedDark: return RGB(r: 0.15, g: 0.55, b: 0.82)
        case .paperLight: return RGB(r: 0.14, g: 0.45, b: 0.88)
        }
    }
}

/// Bounds and defaults persistence for the resizable floating Terminal panel.
public enum TerminalPanelSizeBounds {
    public static let minWidth: CGFloat = 480
    public static let maxWidth: CGFloat = 1100
    public static let minHeight: CGFloat = 280
    public static let maxHeight: CGFloat = 760
    public static let defaultSize = CGSize(width: 680, height: 420)

    public static let widthKey = "com.katikati.terminal.width"
    public static let heightKey = "com.katikati.terminal.height"

    public static func clamped(_ size: CGSize) -> CGSize {
        let w = min(max(size.width, minWidth), maxWidth)
        let h = min(max(size.height, minHeight), maxHeight)
        return CGSize(width: w.rounded(), height: h.rounded())
    }

    public static func load(_ defaults: UserDefaults = .standard) -> CGSize {
        let w = defaults.double(forKey: widthKey)
        let h = defaults.double(forKey: heightKey)
        guard w > 0, h > 0 else { return defaultSize }
        return clamped(CGSize(width: w, height: h))
    }

    public static func save(_ size: CGSize, defaults: UserDefaults = .standard) {
        let c = clamped(size)
        defaults.set(Double(c.width), forKey: widthKey)
        defaults.set(Double(c.height), forKey: heightKey)
    }
}

/// Curated quick command snippets and safe shell cd escaping for Terminal.
public struct TerminalSnippet: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let command: String

    public init(id: String, title: String, command: String) {
        self.id = id
        self.title = title
        self.command = command
    }

    public static let defaultSnippets: [TerminalSnippet] = [
        TerminalSnippet(id: "git-status", title: "Git Status", command: "git status"),
        TerminalSnippet(id: "git-log", title: "Git Log (10)", command: "git log -n 10 --oneline"),
        TerminalSnippet(id: "ls-la", title: "List Hidden Files", command: "ls -la"),
        TerminalSnippet(id: "disk-usage", title: "Folder Sizes", command: "du -sh *"),
        TerminalSnippet(id: "ports", title: "Listening Ports", command: "lsof -iTCP -sTCP:LISTEN"),
    ]

    /// Safely single-quotes a POSIX directory path for shell `cd` execution, rejecting control characters.
    public static func shellEscapedCDCommand(for directory: String) -> String? {
        guard !directory.isEmpty else { return nil }
        for scalar in directory.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                return nil
            }
        }
        let escaped = directory.replacingOccurrences(of: "'", with: "'\\''")
        return "cd '\(escaped)'\n"
    }
}

/// Pure buffer text search helper for Terminal scrollback/screen text.
public enum TerminalBufferSearch {
    public struct Match: Equatable, Sendable {
        public let lineIndex: Int
        public let lineText: String

        public init(lineIndex: Int, lineText: String) {
            self.lineIndex = lineIndex
            self.lineText = lineText
        }
    }

    public static func matches(in bufferText: String, query: String, limit: Int = 50) -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }
        let lines = bufferText.components(separatedBy: .newlines)
        var out: [Match] = []
        for (idx, line) in lines.enumerated() {
            if line.localizedCaseInsensitiveContains(trimmed) {
                out.append(Match(lineIndex: idx, lineText: line.trimmingCharacters(in: .whitespacesAndNewlines)))
                if out.count >= limit { break }
            }
        }
        return out
    }
}
