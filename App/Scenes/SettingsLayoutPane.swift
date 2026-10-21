import SwiftUI

// Phase 6 Layout tab. Every geometry the user sees here comes from `IslandLayoutSolver`
// through `LayoutThumbnailModel`; every control writes an existing `AppSettingsStore`
// setter whose `@Published` value the panel coordinator already relayouts on, so changes
// apply without a relaunch.

/// One mode drawn from the solver: a muted screen with the islands sitting on its bottom edge.

/// Bottom-edge presets for the segmented control. `custom` = any slider value that is
/// neither preset; picking it keeps the current value (or nudges off a preset).
enum BottomEdgeChoice: Hashable {
    case floating, hugging, custom

    init(gap: CGFloat) {
        switch gap {
        case PanelLayoutMetrics.floatingBottomGap: self = .floating
        case PanelLayoutMetrics.huggingBottomGap: self = .hugging
        default: self = .custom
        }
    }
}

struct SettingsLayoutPane: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject var keyGuard = KeyGuardService.shared
    @ObservedObject var notifMove = NotificationMoveService.shared
    @State var newPresetName = ""
    /// Fine-tune starts collapsed: styles + Size/Spacing cover the common choices (Phase 11f).
    @State var showsFineTune = false
    /// The Shortcuts page's find field (Phase 12 A4). Localized titles only, so it matches what
    /// the reader sees in every language.
    @State var shortcutFilter = ""
    /// The two long runs on the Shortcuts page start collapsed: the 26 assignments are 1066 pt
    /// against the page's 986 pt (measured live 2026-10-15), so the page only fits the window with
    /// them closed. `expandedWhileFiltering` opens them for a find query, so search still reaches
    /// every row — nothing is dropped, it is one click (or one keystroke) away.
    @State var showsFeatureShortcuts = false
    @State var showsSnapHotkeys = false
    @State var showsTilingShortcuts = false
    /// The Edge Bars page's Custom item list (one row per item). Collapsed by default — see its card.
    @State var showsEdgeItems = false
    /// Control Center edge; the panel reads it at each open (Phase 16n). The literal duplicates
    /// `ControlCenterPanelController.sideKey` — that file is app-target-only, and this pane also
    /// compiles into the test target.
    @AppStorage("com.katikati.controlcenter.side") var controlCenterSideRaw = EdgeSide.right.rawValue
    @AppStorage("com.katikati.dial.enabled") var dialEnabled: Bool = true
    @AppStorage("com.katikati.dial.theme") var dialThemeRaw: String = RadialDialTheme.lilacGlass.rawValue
    @AppStorage("com.katikati.dial.mouseTrigger") var dialMouseTriggerRaw: String = RadialMouseTrigger.off.rawValue
    @AppStorage("com.katikati.dial.triggerMode") var dialTriggerModeRaw: String = RadialTriggerMode.tapToggle.rawValue
    /// Phase 32b: the dock widgets' motion language (Dock Items tab since 2026-10-20).
    @AppStorage(WidgetMotionPreset.storageKey) var dockMotion: WidgetMotionPreset = .default



    /// Width styles are fitted to: the screen the dock is on (main until it reports).
    var dockScreenWidth: CGFloat { NSScreen.main?.frame.width ?? LayoutThumbnailModel.referenceScreen.width }

    /// Phase 12e — one pane, several tabs: Appearance embeds the dock geometry, Widgets takes
    /// the widget list, presets and styles.
    enum Mode { case radialDial, shortcuts, widgets, edgeBars, geometry, chips, launcher, controlCenter, notifications }
    var mode: Mode = .shortcuts

    var body: some View {
        let inputs = store.layoutThumbnailInputs
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            if mode == .widgets {
                widgetSections
            } else if mode == .edgeBars {
                edgeBarSections
            } else if mode == .geometry {
                geometrySections
            } else if mode == .chips {
                chipSections
            } else if mode == .launcher {
                launcherSections
            } else if mode == .controlCenter {
                controlCenterSections
            } else if mode == .notifications {
                notificationSections
            } else if mode == .radialDial {
                radialDialSections
            } else {
                shortcutSections
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            let hidden = LauncherStore(url: LauncherStore.defaultURL).load().hidden
            launcherHiddenCount = hidden.count
            launcherHiddenIDs = Set(hidden)
        }
    }

    /// The fifteen snap zones in the four groups the page captions (Halves, Quarters, Thirds,
    /// Full). One list, so the page and its "is anything left after filtering" check cannot drift,
    /// and `Tests/Unit/ShortcutsTests.swift` pins that it is every snap zone exactly once.
    static let snapHotkeyGroups: [[ShortcutAction]] = [
        [.snapLeftHalf, .snapRightHalf, .snapTopHalf, .snapBottomHalf],
        [.snapTopLeft, .snapTopRight, .snapBottomLeft, .snapBottomRight],
        [.snapLeftThird, .snapCenterThird, .snapRightThird, .snapLeftTwoThirds, .snapRightTwoThirds],
        [.snapCenter, .snapMaximize, .snapNextDisplay],
    ]

    /// Matching is on the localized name, so a search for what the reader sees works in all twelve
    /// languages. The rule itself is static and pinned by `Tests/Unit/ShortcutsTests.swift`.
    static func shortcutMatches(_ name: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        // `localizedStandardContains` is the comparison a search field wants: case- and
        // diacritic-insensitive, so typing "cafe" finds "Café".
        return name.localizedStandardContains(trimmed)
    }

    /// The action's name in one place, as a `String`: the row label, the VoiceOver label and the
    /// find field all need the same text, and a search field can only match a string
    /// (`String(localized:)` keeps the literal visible to `Scripts/check_localization.py`). Static,
    /// so `Tests/Unit/ShortcutsTests.swift` can pin that no two actions wear one name.
    static func shortcutActionName(_ action: ShortcutAction) -> String {
        switch action {
        case .launcher: return String(localized: "Launcher")
        case .pinboard: return String(localized: "Control Center")
        case .quickSettings: return String(localized: "Quick Settings")
        case .keepAwake: return String(localized: "Keep Awake")
        case .drawer: return String(localized: "Drawer")
        case .notchTools: return String(localized: "Notch Tools")
        case .weather: return String(localized: "Weather")
        case .clock: return String(localized: "Clock")
        case .commandBar: return String(localized: "Command Bar")
        case .translate: return String(localized: "Translate")
        // Phase 26a snap zones
        case .snapLeftHalf: return String(localized: "Snap Left Half")
        case .snapRightHalf: return String(localized: "Snap Right Half")
        case .snapTopHalf: return String(localized: "Snap Top Half")
        case .snapBottomHalf: return String(localized: "Snap Bottom Half")
        case .snapTopLeft: return String(localized: "Snap Top-Left")
        case .snapTopRight: return String(localized: "Snap Top-Right")
        case .snapBottomLeft: return String(localized: "Snap Bottom-Left")
        case .snapBottomRight: return String(localized: "Snap Bottom-Right")
        case .snapLeftThird: return String(localized: "Snap Left Third")
        case .snapCenterThird: return String(localized: "Snap Center Third")
        case .snapRightThird: return String(localized: "Snap Right Third")
        case .snapLeftTwoThirds: return String(localized: "Snap Left Two-Thirds")
        case .snapRightTwoThirds: return String(localized: "Snap Right Two-Thirds")
        case .snapCenter: return String(localized: "Snap Center")
        case .snapMaximize: return String(localized: "Snap Maximize")
        case .snapNextDisplay: return String(localized: "Move to Next Display")
        // Phase 26b tiling actions
        case .toggleTiling: return String(localized: "Toggle Tiling")
        case .cycleTilingLayout: return String(localized: "Cycle Tiling Layout")
        case .tilingFocusNext: return String(localized: "Focus Next Tile")
        case .tilingFocusPrevious: return String(localized: "Focus Previous Tile")
        case .tilingSwapNext: return String(localized: "Swap with Next Tile")
        case .tilingSwapPrevious: return String(localized: "Swap with Previous Tile")
        case .tilingGrowMain: return String(localized: "Grow Main Tile")
        case .tilingShrinkMain: return String(localized: "Shrink Main Tile")
        case .tilingFlipMain: return String(localized: "Flip Main Tile Side")
        case .radialDial: return String(localized: "Radial Dial")
        case .radialDialSnap: return String(localized: "Radial Dial: Snapping")
        case .radialDialTools: return String(localized: "Radial Dial: Tools")
        case .notchPageNext: return String(localized: "Next Notch Page")
        case .notchPagePrevious: return String(localized: "Previous Notch Page")
        case .captureArea: return String(localized: "Capture Area")
        }
    }

    static func presetTitle(_ preset: EdgeBarPreset) -> Text {
        switch preset {
        case .off: return Text("Off")
        case .notes: return Text("Notes")
        case .notesAndStatus: return Text("Notes & Status")
        case .status: return Text("Status")
        case .productivityAndRest: return Text("Productivity + Rest")
        case .custom: return Text("Custom")
        }
    }

    @State var launcherHiddenCount = 0
    @State var launcherHiddenIDs: Set<String> = []

    static func itemTitle(_ item: EdgeItem) -> Text {
        switch item {
        case .notes: return Text("Notes")
        case .newNote: return Text("New Note")
        case .settings: return Text("KatiKati Settings")
        case .status: return Text("Status")
        case .weather: return Text("Weather")
        case .nowPlaying: return Text("Now Playing")
        case .bluetooth: return Text("Bluetooth")
        case .systemMonitor: return Text("System")
        case .reminders: return Text("Reminders")
        case .alarms: return Text("Alarms")
        case .time: return Text("Time")
        case .tasks: return Text("Tasks")
        case .clipboard: return Text("Clipboard")
        case .capture: return Text("Capture")
        case .windows: return Text("Windows")
        case .screenshot: return Text("Copy Screenshot")
        case .screenTime: return Text("Screen Time")
        }
    }

    static func appName(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func runningAppChoices(excluding: Set<String>) -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (bundleID: String, name: String)? in
                guard let bid = app.bundleIdentifier, !excluding.contains(bid) else { return nil }
                return (bid, app.localizedName ?? bid)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// A reorderable row's own height, and its pitch: one row of the page's grid — a 24 pt control
    /// (measured on all ten pages, `evidence/2026-10-15-close-out/*-rows.txt`) with the grid's padding
    /// each side and its 1 pt divider, 41 pt (`Docs/SETTINGS.md` rule 1). Derived from
    /// `SettingsMetrics`, not fixed, so the list stays on the page's rhythm (F1).
    /// 6 pt each side, not the grid's 8 (2026-10-18): the row's own control is 24 pt either way, and
    /// at 41 pt per row this list cost the page the 13 pt it was over by with the context presets on.
    static let widgetRowHeight: CGFloat = 24 + 2 * 6 + 1
    /// The plain `List`'s own leading indentation, which `.listRowInsets` does not reach.
    static let listRowChromeInset: CGFloat = 8

    static func widgetListHeight(count: Int) -> CGFloat {
        CGFloat(count) * widgetRowHeight
    }

}

