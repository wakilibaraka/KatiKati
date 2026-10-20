import Foundation

// Phase 33c — NotchSectionPaging: 5-page bento gallery structure, discrete row paging,
// and context-aware default page opening logic. Dual-compiled.

/// The dedicated pages of the redesigned Dynamic Island Notch bento gallery: five always-on pages, plus
/// the teleprompter and the camera mirror, which exist only while their own switch is on.
enum NotchPage: Int, CaseIterable, Identifiable, Sendable {
    case downloadDeck = 0   // Page 1: Download Manager & Torrent Hub
    case storage = 1        // Page 2: Storage Analyzer (largest items on the Mac)
    case aiTracker = 2      // Page 3: AI Mission Control (Claude, Codex, OpenCode, Copilot)
    case audioDeck = 3      // Page 4: Music & Calendar
    case teleprompter = 4   // Only present while the owner turns it on
    case cameraMirror = 5   // The live camera mirror, only while it is switched on
    case notifications = 6  // Mirrored notifications, only while it is switched on

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .aiTracker: return "AI Mission Control"
        case .audioDeck: return "Music & Calendar"
        case .storage: return String(localized: "Storage")
        case .downloadDeck: return "Downloads & Torrents"
        case .teleprompter: return "Teleprompter"
        // Localised at the source: the title is rendered as data (`Text(page.title)`), so a bare literal
        // would ship English in every language — and the catalog gate reads it as an unreferenced key.
        case .cameraMirror: return String(localized: "Camera Mirror")
        case .notifications: return String(localized: "Notifications")
        }
    }

    var symbol: String {
        switch self {
        case .aiTracker: return "sparkles"
        case .audioDeck: return "music.note"
        case .storage: return "internaldrive.fill"
        case .downloadDeck: return "arrow.down.circle.fill"
        case .teleprompter: return "text.alignleft"
        case .cameraMirror: return "camera.viewfinder"
        case .notifications: return "bell.fill"
        }
    }

    /// The pages in paging order. The teleprompter, the camera mirror and the notifications page exist
    /// only while their own switch is on, so with all three off the gallery is exactly the five pages it
    /// always was.
    static func visible(teleprompter: Bool, mirror: Bool = false, notifications: Bool = false,
                        layout: NotchPageLayout = .stored) -> [NotchPage] {
        layout.apply(allCases.filter { page in
            switch page {
            case .teleprompter: return teleprompter
            case .cameraMirror: return mirror
            case .notifications: return notifications
            default: return true
            }
        })
    }

    func next(wrap: Bool = true, teleprompter: Bool = false, mirror: Bool = false,
              notifications: Bool = false) -> NotchPage {
        let all = Self.visible(teleprompter: teleprompter, mirror: mirror, notifications: notifications)
        guard let index = all.firstIndex(of: self) else { return all[0] }
        if index + 1 < all.count { return all[index + 1] }
        return wrap ? all[0] : self
    }

    func previous(wrap: Bool = true, teleprompter: Bool = false, mirror: Bool = false,
                  notifications: Bool = false) -> NotchPage {
        let all = Self.visible(teleprompter: teleprompter, mirror: mirror, notifications: notifications)
        guard let index = all.firstIndex(of: self) else { return all[0] }
        if index > 0 { return all[index - 1] }
        return wrap ? all[all.count - 1] : self
    }
}

/// 51c: the owner's page order and hidden pages, stored as "order|hidden" (raw values, comma separated).
struct NotchPageLayout: Equatable, Sendable {
    static let defaultsKey = "com.katikati.notch.pageOrder"
    static var stored: NotchPageLayout { NotchPageLayout(raw: UserDefaults.standard.string(forKey: defaultsKey) ?? "") }

    /// Always a permutation of every page: unknown or repeated values are dropped, missing pages appended.
    private(set) var order: [NotchPage]
    var hidden: Set<NotchPage>

    init(order: [NotchPage] = NotchPage.allCases, hidden: Set<NotchPage> = []) {
        var seen = Set<NotchPage>()
        self.order = (order + NotchPage.allCases).filter { seen.insert($0).inserted }
        self.hidden = hidden
    }

    init(raw: String) {
        func pages(_ part: Substring) -> [NotchPage] { part.split(separator: ",").compactMap { Int($0).flatMap(NotchPage.init(rawValue:)) } }
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        self.init(order: parts.first.map(pages) ?? [], hidden: Set(parts.count > 1 ? pages(parts[1]) : []))
    }

    var raw: String { order.map { String($0.rawValue) }.joined(separator: ",") + "|" + hidden.map { String($0.rawValue) }.sorted().joined(separator: ",") }

    /// The pages reordered and minus the hidden ones. Never empty while `pages` is not: when every page is
    /// hidden the notch is switched off by the settings, and the gallery must still have a page to stand on.
    func apply(_ pages: [NotchPage]) -> [NotchPage] {
        let sorted = pages.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
        let shown = sorted.filter { !hidden.contains($0) }
        return shown.isEmpty ? sorted : shown
    }
}

/// +1 when paging forward, -1 when paging back. Used for directional slide transitions
/// so a swipe/header/dot jump animates the way the pointer moved.
enum NotchPageDirection {
    static func between(from: NotchPage, to: NotchPage, visible: [NotchPage]) -> Int {
        guard let a = visible.firstIndex(of: from), let b = visible.firstIndex(of: to), a != b else { return 1 }
        // Wrap jumps (last -> first, first -> last) keep the swipe's wrap direction.
        if a == visible.count - 1, b == 0 { return 1 }
        if a == 0, b == visible.count - 1 { return -1 }
        return b > a ? 1 : -1
    }
}

/// Dynamic context-aware default page resolver.
enum NotchPagingPolicy {
    static func defaultPage(
        nowPlayingActive: Bool,
        aiTurnActive: Bool,
        downloadsActive: Bool = false,
        userPinnedPage: NotchPage? = nil
    ) -> NotchPage {
        if let pinned = userPinnedPage { return pinned }
        if downloadsActive { return .downloadDeck }
        if aiTurnActive { return .aiTracker }
        if nowPlayingActive { return .audioDeck }
        return .downloadDeck
    }
}

/// Pure Companion State policy:
/// When Notch is active / expanded, the dock capsule auto-hides or dims to avoid visual duplication.
enum NotchDockCompanionPolicy {
    static func shouldHideDockCapsule(notchExpanded: Bool, dockCompanionAutoHide: Bool = true) -> Bool {
        dockCompanionAutoHide && notchExpanded
    }
}

/// Wheel and trackpad input accumulator for horizontal page stepping.
struct NotchSectionScroll: Sendable {
    static let firstStep: Double = 24.0
    static let pageStep: Double = 60.0
    static let sequenceGap: TimeInterval = 0.35

    private var distance: Double = 0.0
    private var direction: Int = 0
    private var stepped: Bool = false
    private var lastTimestamp: TimeInterval?

    /// Steps to move across pages; positive = forward (next), negative = backward (previous).
    mutating func steps(
        deltaX: Double,
        timestamp: TimeInterval,
        precise: Bool,
        hasPhase: Bool,
        began: Bool,
        ended: Bool,
        momentum: Bool
    ) -> Int {
        guard deltaX.isFinite, timestamp.isFinite else { self = Self(); return 0 }
        if momentum { return 0 }
        if ended { self = Self(); return 0 }
        guard precise else {
            self = Self()
            return deltaX == 0 ? 0 : (deltaX < 0 ? 1 : -1)
        }
        if began || lastTimestamp.map({ timestamp < $0 || (!hasPhase && timestamp - $0 > Self.sequenceGap) }) == true {
            self = Self()
        }
        lastTimestamp = timestamp
        if deltaX != 0 {
            let incomingDirection = deltaX < 0 ? 1 : -1
            if direction != 0, direction != incomingDirection { distance = 0; stepped = false }
            direction = incomingDirection
        }
        distance += deltaX
        var steps = 0
        let threshold = stepped ? Self.pageStep : Self.firstStep
        while abs(distance) >= threshold {
            distance = distance > 0 ? distance - threshold : distance + threshold
            stepped = true
            steps += 1
        }
        return direction * steps
    }
}
