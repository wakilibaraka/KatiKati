import Foundation

/// A video-call service the dock can send you to straight from a calendar event.
enum MeetingProvider: String, CaseIterable, Sendable {
    case zoom
    case googleMeet
    case teams

    /// Brand-free SF Symbol; the provider name rides next to it as text.
    var symbolName: String { "video.fill" }

    func matches(host: String, path: String) -> Bool {
        switch self {
        case .zoom:
            return host == "zoom.us" || host.hasSuffix(".zoom.us") || host.hasSuffix(".zoomgov.com")
        case .googleMeet:
            return host == "meet.google.com" && path.count > 1 && !path.hasPrefix("/landing")
        case .teams:
            return (host == "teams.microsoft.com" && (path.hasPrefix("/l/meetup-join") || path.hasPrefix("/meet/")))
                || host == "teams.live.com" || host == "teams.microsoft.us"
        }
    }
}

/// The join link found in an event's URL / location / notes.
struct MeetingLink: Equatable, Sendable {
    let provider: MeetingProvider
    let url: URL

    /// First recognised video-call link across `fields`, searched in order (give the event's own URL first, then
    /// location, then notes). Notes from Outlook arrive HTML-escaped and wrapped in Safe Links, so each field is also
    /// scanned unescaped and percent-decoded.
    static func detect(in fields: [String?]) -> MeetingLink? {
        for field in fields.compactMap({ $0 }) where !field.isEmpty {
            let unescaped = field.replacingOccurrences(of: "&amp;", with: "&")
            for text in [unescaped, unescaped.removingPercentEncoding].compactMap({ $0 }) {
                if let link = firstLink(in: text) { return link }
            }
        }
        return nil
    }

    /// Lookahead so matches overlap: a link wrapped in a redirect (`?url=https://teams…`) is found as its own match.
    private static let urlPattern = try? NSRegularExpression(pattern: #"(?=((?:https?|zoommtg|zoomus)://[^\s<>"'\)\]]+))"#)

    private static func firstLink(in text: String) -> MeetingLink? {
        guard let urlPattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in urlPattern.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range(at: 1), in: text) else { continue }
            let raw = String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?>"))
            guard let url = URL(string: raw), let host = url.host?.lowercased() else { continue }
            if url.scheme == "zoommtg" || url.scheme == "zoomus" { return MeetingLink(provider: .zoom, url: url) }
            if let provider = MeetingProvider.allCases.first(where: { $0.matches(host: host, path: url.path) }) {
                return MeetingLink(provider: provider, url: url)
            }
        }
        return nil
    }
}

// MARK: - Notch Call HUD & Meeting Controls (Slice A-CallHUD)

/// Video-conferencing and call platform recognized by KatiKati's Notch Call HUD.
enum MeetingCallPlatform: String, CaseIterable, Sendable, Codable {
    case zoom
    case googleMeet
    case teams
    case faceTime
    case webex

    var displayName: String {
        switch self {
        case .zoom: return "Zoom"
        case .googleMeet: return "Google Meet"
        case .teams: return "Microsoft Teams"
        case .faceTime: return "FaceTime"
        case .webex: return "Webex"
        }
    }

    var sfSymbol: String {
        "video.fill"
    }

    var primaryBundleIdentifiers: [String] {
        switch self {
        case .zoom:
            return ["us.zoom.xos"]
        case .googleMeet:
            return ["com.google.Chrome", "com.apple.Safari", "com.brave.Browser"]
        case .teams:
            return ["com.microsoft.teams2", "com.microsoft.teams"]
        case .faceTime:
            return ["com.apple.FaceTime"]
        case .webex:
            return ["com.cisco.webexmeetingsapp", "Cisco-Systems.Spark"]
        }
    }
}

/// Actions available from the Notch meeting control bar.
enum MeetingCallAction: String, CaseIterable, Sendable {
    case toggleMute
    case toggleCamera
    case endCall
}

/// Keyboard shortcut representation for meeting platform control.
struct MeetingShortcut: Equatable, Sendable {
    let keyEquivalent: String
    let modifierFlags: [String]
    let label: String

    init(keyEquivalent: String, modifierFlags: [String], label: String) {
        self.keyEquivalent = keyEquivalent
        self.modifierFlags = modifierFlags
        self.label = label
    }
}

/// Pure routing logic mapping meeting platform + action to keyboard commands.
enum NotchMeetingControlRouter {
    static func shortcut(for action: MeetingCallAction, on platform: MeetingCallPlatform) -> MeetingShortcut {
        switch (platform, action) {
        case (.zoom, .toggleMute):
            return MeetingShortcut(keyEquivalent: "a", modifierFlags: ["command", "shift"], label: "⌘⇧A")
        case (.zoom, .toggleCamera):
            return MeetingShortcut(keyEquivalent: "v", modifierFlags: ["command", "shift"], label: "⌘⇧V")
        case (.zoom, .endCall):
            return MeetingShortcut(keyEquivalent: "w", modifierFlags: ["command"], label: "⌘W")

        case (.googleMeet, .toggleMute):
            return MeetingShortcut(keyEquivalent: "d", modifierFlags: ["command"], label: "⌘D")
        case (.googleMeet, .toggleCamera):
            return MeetingShortcut(keyEquivalent: "e", modifierFlags: ["command"], label: "⌘E")
        case (.googleMeet, .endCall):
            return MeetingShortcut(keyEquivalent: "w", modifierFlags: ["command"], label: "⌘W")

        case (.teams, .toggleMute):
            return MeetingShortcut(keyEquivalent: "m", modifierFlags: ["command", "shift"], label: "⌘⇧M")
        case (.teams, .toggleCamera):
            return MeetingShortcut(keyEquivalent: "o", modifierFlags: ["command", "shift"], label: "⌘⇧O")
        case (.teams, .endCall):
            return MeetingShortcut(keyEquivalent: "h", modifierFlags: ["command", "shift"], label: "⌘⇧H")

        case (.faceTime, .toggleMute):
            return MeetingShortcut(keyEquivalent: "m", modifierFlags: ["command", "shift"], label: "⌘⇧M")
        case (.faceTime, .toggleCamera):
            return MeetingShortcut(keyEquivalent: "v", modifierFlags: ["command", "shift"], label: "⌘⇧V")
        case (.faceTime, .endCall):
            return MeetingShortcut(keyEquivalent: "w", modifierFlags: ["command"], label: "⌘W")

        case (.webex, .toggleMute):
            return MeetingShortcut(keyEquivalent: "m", modifierFlags: ["command", "shift"], label: "⌘⇧M")
        case (.webex, .toggleCamera):
            return MeetingShortcut(keyEquivalent: "v", modifierFlags: ["command", "shift"], label: "⌘⇧V")
        case (.webex, .endCall):
            return MeetingShortcut(keyEquivalent: "l", modifierFlags: ["command"], label: "⌘L")
        }
    }
}

/// Pure state snapshot of an active call.
struct MeetingCallState: Equatable, Sendable {
    let id: String
    let platform: MeetingCallPlatform
    let title: String
    var isMicMuted: Bool
    var isCameraOff: Bool
    let startTime: Date

    init(
        id: String = UUID().uuidString,
        platform: MeetingCallPlatform,
        title: String = "",
        isMicMuted: Bool = false,
        isCameraOff: Bool = false,
        startTime: Date = Date()
    ) {
        self.id = id
        self.platform = platform
        self.title = title.isEmpty ? platform.displayName : title
        self.isMicMuted = isMicMuted
        self.isCameraOff = isCameraOff
        self.startTime = startTime
    }

    func formattedDuration(at currentTime: Date) -> String {
        let elapsed = max(0, Int(currentTime.timeIntervalSince(startTime)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMinutes = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remMinutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func toggledMute() -> MeetingCallState {
        var copy = self
        copy.isMicMuted.toggle()
        return copy
    }

    func toggledCamera() -> MeetingCallState {
        var copy = self
        copy.isCameraOff.toggle()
        return copy
    }
}

/// Policy for matching active running app bundle IDs to meeting platforms.
enum MeetingDetectionPolicy {
    static func detectPlatform(fromRunningBundleIDs bundleIDs: [String]) -> MeetingCallPlatform? {
        let set = Set(bundleIDs.map { $0.lowercased() })

        // Dedicated desktop call apps have highest priority
        if set.contains("us.zoom.xos") { return .zoom }
        if set.contains("com.apple.facetime") { return .faceTime }
        if set.contains("com.microsoft.teams2") || set.contains("com.microsoft.teams") { return .teams }
        if set.contains("com.cisco.webexmeetingsapp") { return .webex }

        return nil
    }
}
