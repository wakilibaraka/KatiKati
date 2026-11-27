import Foundation

/// Ranked fuzzy, synonym, and row-content search index for Settings sidebar and Launcher Settings results.
enum SettingsSearchIndex {
    private static let synonyms: [String: [String]] = [
        "autohide": ["hide dock", "dock position", "edge auto hide", "reveal delay"],
        "auto-hide": ["hide dock", "dock position", "reveal delay"],
        "tile": ["tiling", "snap", "gaps", "bsp", "monocle"],
        "snap": ["tiling", "zones", "shortcuts", "aero"],
        "aero": ["tiling", "snap", "window management"],
        "raycast": ["command bar", "launcher", "spotlight", "alfred"],
        "alfred": ["launcher", "command bar", "spotlight"],
        "spotlight": ["launcher", "search", "command bar"],
        "bartender": ["menu bar", "status items", "creative hub"],
        "menubar": ["menu bar", "status trio", "drives"],
        "tray": ["shelf", "file tray", "menu bar"],
        "notchy": ["notch", "live island", "dynamic island"],
        "island": ["notch", "live island", "dock island"],
        "dynamic": ["notch", "wallpaper", "resizing"],
        "background": ["wallpaper", "appearance", "theme", "backdrop"],
        "glass": ["appearance", "theme", "vibrancy", "translucency", "liquid glass"],
        "spaces": ["experimental", "mission control", "space names", "switch"],
        "expose": ["mission control", "experimental", "overview"],
        "beta": ["experimental", "private api", "mission control", "lock screen", "album art"],
        "wings": ["dock layout", "widget wings", "flanking", "telemetry", "ram"],
        "hotkey": ["keyboard shortcuts", "keybind", "recorder"],
        "keybind": ["keyboard shortcuts", "shortcuts", "finder keys"],
        "rename": ["finder keys", "f2", "cut", "paste"],
        "download": ["downloads", "torrent", "aria2", "hydra"],
        "dict": ["dictionary", "translate", "tools"],
        "easydict": ["dictionary", "tools", "side deck"],
        "cleardisk": ["drives", "storage", "menu bar", "side deck"],
        "colors": ["colour", "theme", "tint", "appearance"],
        "colorspace": ["theme", "tint", "appearance"]
    ]

    /// Actual control row labels and in-card terms indexed per Settings tab so typing a row label jumps straight there.
    static let rowContentByTab: [SettingsTab: [String]] = [
        .general: ["Launch at login", "Language", "Automatic Updates", "Accessibility", "Screen Recording", "Input Monitoring", "Backup & Sync", "WebDAV", "Open Setup Guide", "Diagnostic Report"],
        .menuBar: ["Menu Bar Icon", "Status Trio Ring", "Left-Click Creative Hub", "Right-Click Menu", "Drives", "CPU", "Memory", "GPU", "Network", "Battery"],
        .appearance: ["Layout Mode", "Bar Height", "Spacing", "Theme", "Vibrancy", "Contrast", "Translucency", "Follow Dock Theme", "Space Switching"],
        .wallpaper: ["Dynamic Wallpaper", "Time of Day", "Weather Sky", "Dock Accent"],
        .dockItems: ["Dock Position", "Hide Dock", "Animation Delay", "Animation Speed", "Profiles", "Dock Layout", "Detached Capsule", "Background & Activity Icon", "Mid-Dock Utilities", "Utility Popups", "Widget Wings", "Left Wing", "Right Wing", "Wing Spacing"],
        .appIcons: ["Instance Presets", "Symmetrical Spacing", "Dynamic Resizing", "App Groups", "Auto-Group Apps", "Keep in Dock", "Hover Animation"],
        .shelf: ["Shake to Shelf", "Notch File Tray", "Shelf Storage", "Expire Unpinned", "Space Pinning"],
        .barWidgets: ["Weather", "Now Playing", "Clock", "Calendar", "System", "Devices", "Drives", "Context Presets", "Right FAB Style"],
        .desktop: ["Desktop Boxes", "Folder Boxes", "To-Do", "Notes", "Glance", "Identify Displays"],
        .weather: ["Temperature Unit", "Wind Speed", "Weather Style", "Samsung", "Orion", "Not Boring", "Heat Warning", "Snow Warning"],
        .music: ["Desktop Music Widget", "Show on Desktop", "Theme", "Scrubber", "Card Layout", "Synced Lyrics", "Discord Rich Presence"],
        .notch: ["Live Island", "Notch Skin", "Notch Helpers", "Peripherals HUD", "Hardware Takeover"],
        .notifications: ["Battery Alerts", "Charging", "Bluetooth Peripherals", "Banner Placement"],
        .sideDeck: ["Edge Activation", "Weather Handle Pill", "Deck Width", "Swap Left / Right Sides", "Open Side Deck at Screen Edge"],
        .edgeBars: ["Edge Bars", "Preset", "Sydedock", "ExtraDock", "Keep Edge Bars Open", "Collapse to Single Button"],
        .tiling: ["Auto-Tiling", "Tiling Presets", "Inner Gaps", "Outer Gaps", "Floating Apps"],
        .windowManagement: ["Window Chips", "Window Inspector", "Snap Zones", "Desktop Window Box", "Focus Border", "Restore Layout After Sleep"],
        .launcher: ["Global Search", "File Indexing", "Hidden Apps", "Result Limit"],
        .commandBar: ["Command Bar", "Script Commands", "Hints"],
        .controlCenter: ["Control Center", "Tiles", "Placement", "Quick Toggles"],
        .shortcuts: ["Keyboard Shortcuts", "Capture Area", "Capture Window", "Window Inspector", "Side Deck"],
        .keyboard: ["Hyper Key", "Caps Lock", "Finder Keys", "Cut & Paste", "F2 Rename", "Paste Image", "Pause Keyboard", "Cleaning Mode"],
        .keyVisualizer: ["Key Visualizer", "Show Mouse Clicks", "Linger", "Filter", "Position"],
        .mouse: ["Focus Follows Mouse", "Natural Scroll", "Click Feedback"],
        .mouseGestures: ["Trackpad Gestures", "Three-Finger Swipe", "Pinch", "Live Visualizer"],
        .radialDial: ["Radial Dial", "Pie Menu", "Slices", "Dial Theme"],
        .quitApps: ["Hold Command-Q", "Quit Confirmation", "Quit on Last Window Close", "Idle Apps"],
        .aiTracking: ["Claude Code", "Codex", "Token Budget", "Approval Hook", "Telemetry"],
        .downloads: ["Download Manager", "Torrents", "aria2", "Bandwidth Limit", "Quiet Hours"],
        .clipboard: ["Clipboard History", "Pin Items", "Plain Text Paste", "Ignore Apps", "Retention"],
        .tools: ["Calculator", "Date Calculator", "Teleprompter", "Snippets", "Cheat Sheet"],
        .experimental: ["Mission Control Overlay", "Space Names", "Window Borders", "Tint Wash", "Hover Actions", "Lock Screen Card", "Album Art Wallpaper", "Classic Static Backdrop", "Animated Album Art", "Private APIs"],
        .advanced: ["Reset Settings", "Debug Switches", "Permissions", "Side Deck Edge Hover"]
    ]

    static func matchingTabs(for rawQuery: String, in tabs: [SettingsTab] = SettingsTab.allCases) -> [SettingsTab] {
        let query = normalized(rawQuery)
        guard !query.isEmpty else { return tabs }
        let queryTokens = tokens(from: query)
        let expandedTerms = queryTokens.flatMap { token -> [String] in
            [token] + (synonyms[token] ?? [])
        }

        let scored: [(tab: SettingsTab, score: Int, index: Int)] = tabs.enumerated().compactMap { index, tab in
            let s = score(tab: tab, query: query, tokens: queryTokens, expandedTerms: expandedTerms)
            guard s > 0 else { return nil }
            return (tab, s, index)
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.index < rhs.index
            }
            .map(\.tab)
    }

    /// Best search term to scroll/highlight inside `tab` once opened from the sidebar.
    static func resolvedRowQuery(for tab: SettingsTab, userQuery rawQuery: String) -> String {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "" }
        let rows = rowContentByTab[tab] ?? []
        if rows.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
            return query
        }
        let qNorm = normalized(query)
        let qTokens = tokens(from: qNorm)
        let expanded = qTokens + qTokens.flatMap { synonyms[$0] ?? [] }
        for term in expanded {
            if let bestRow = rows.first(where: { normalized($0).contains(term) }) {
                return bestRow
            }
        }
        return query
    }

    private static func score(tab: SettingsTab, query: String, tokens queryTokens: [String], expandedTerms: [String]) -> Int {
        let titleNorm = normalized(tab.title)
        let titleTokens = tokens(from: titleNorm)
        let subtitleNorm = normalized(tab.subtitle)
        let termsNorm = normalized(tab.searchTerms)
        let rows = (rowContentByTab[tab] ?? []).map(normalized)
        let rowTokens = rows.flatMap { tokens(from: $0) }
        let combined = ([titleNorm, subtitleNorm, termsNorm] + rows).joined(separator: " ")
        let haystackTokens = tokens(from: combined)

        var best = 0
        if titleNorm == query {
            best = max(best, 1000)
        } else if titleNorm.hasPrefix(query) {
            best = max(best, 850)
        } else if titleNorm.contains(query) {
            best = max(best, 720)
        }

        if rows.contains(where: { $0.contains(query) }) {
            best = max(best, 640)
        }
        if termsNorm.contains(query) || subtitleNorm.contains(query) {
            best = max(best, 560)
        }

        // All query tokens must be satisfied via direct substring, synonym expansion, fuzzy edit distance <= 1, or subsequence.
        if !queryTokens.isEmpty {
            var tokenScore = 0
            var allMatched = true
            for qTok in queryTokens {
                let candidates = [qTok] + (synonyms[qTok] ?? [])
                var localBest = 0
                for cand in candidates {
                    let candWeight = cand == qTok ? 1.0 : 0.85
                    if titleNorm.contains(cand) {
                        localBest = max(localBest, Int(520 * candWeight))
                    } else if cand.count >= 4, titleTokens.contains(where: { editDistanceAtMostOne($0, cand) }) {
                        localBest = max(localBest, Int(460 * candWeight))
                    } else if rows.contains(where: { $0.contains(cand) }) {
                        localBest = max(localBest, Int(380 * candWeight))
                    } else if cand.count >= 4, rowTokens.contains(where: { editDistanceAtMostOne($0, cand) }) {
                        localBest = max(localBest, Int(300 * candWeight))
                    } else if combined.contains(cand) {
                        localBest = max(localBest, Int(280 * candWeight))
                    } else if cand.count >= 4, haystackTokens.contains(where: { editDistanceAtMostOne($0, cand) }) {
                        localBest = max(localBest, Int(220 * candWeight))
                    }
                }
                if localBest == 0 {
                    allMatched = false
                    break
                }
                tokenScore += localBest
            }
            if allMatched {
                best = max(best, tokenScore)
            }
        }

        if best == 0 && query.count >= 4 {
            if isOrderedSubsequence(query, in: titleNorm) || rows.contains(where: { isOrderedSubsequence(query, in: $0) }) {
                best = 120
            }
        }
        return best
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "&", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func tokens(from normalizedText: String) -> [String] {
        normalizedText
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func isOrderedSubsequence(_ needle: String, in haystack: String) -> Bool {
        var needleIdx = needle.startIndex
        for ch in haystack {
            guard needleIdx < needle.endIndex else { return true }
            if ch == needle[needleIdx] {
                needleIdx = needle.index(after: needleIdx)
            }
        }
        return needleIdx == needle.endIndex
    }

    /// True if `a` and `b` differ by at most 1 insertion, deletion, substitution, or adjacent transposition.
    static func editDistanceAtMostOne(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let lhs = Array(a)
        let rhs = Array(b)
        if abs(lhs.count - rhs.count) > 1 { return false }

        if lhs.count == rhs.count {
            var diffs: [Int] = []
            for i in lhs.indices where lhs[i] != rhs[i] {
                diffs.append(i)
                if diffs.count > 2 { return false }
            }
            if diffs.count == 1 { return true }
            if diffs.count == 2 {
                let i = diffs[0], j = diffs[1]
                return j == i + 1 && lhs[i] == rhs[j] && lhs[j] == rhs[i]
            }
            return false
        }

        let shorter = lhs.count < rhs.count ? lhs : rhs
        let longer = lhs.count < rhs.count ? rhs : lhs
        var i = 0, j = 0, edits = 0
        while i < shorter.count && j < longer.count {
            if shorter[i] == longer[j] {
                i += 1
                j += 1
            } else {
                edits += 1
                if edits > 1 { return false }
                j += 1
            }
        }
        return true
    }
}
