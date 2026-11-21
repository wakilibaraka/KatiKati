import AppKit
import Combine
import Foundation

/// The Shortcut Cheat Sheet coordinator: reads the frontmost app's menu bar shortcuts
/// off the main thread via `AppMenuSearchReader`, merges KatiKati's active global shortcuts, and
/// drives `ShortcutCheatSheetOverlayController`.
@MainActor
final class ShortcutCheatSheetService: ObservableObject {
    static let shared = ShortcutCheatSheetService()
    static let triggerKey = "com.katikati.cheatSheet.trigger"

    @Published private(set) var trigger: ShortcutCheatSheetTrigger = {
        ShortcutCheatSheetTrigger(rawValue: UserDefaults.standard.string(forKey: ShortcutCheatSheetService.triggerKey) ?? "") ?? .off
    }()
    @Published private(set) var isVisible = false
    @Published var isPinned = false
    @Published private(set) var appName = ""
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var isLoading = false
    @Published private(set) var categories: [ShortcutCheatSheetCategory] = []
    @Published var searchQuery = ""
    @Published var liveModifiers: KeyModifiers = []

    private var targetPID: pid_t = 0
    private var katikatiBindings: [ShortcutAction: ShortcutTrigger] = [:]
    private var cache: [pid_t: (at: Date, entries: [MenuSearchEntry])] = [:]
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var holdWork: DispatchWorkItem?
    private var lastCmdUpAt: Date?
    private var cmdIsDown = false
    private var overlay: ShortcutCheatSheetOverlayController?

    /// Whether the panel the service drives is actually on screen, and which window it is — the same
    /// number across entry points is what proves they all share one panel. Read by the live check.
    var isOverlayOnScreen: Bool { overlay?.isPanelVisible ?? false }
    var overlayWindowNumber: Int? { overlay?.panelWindowNumber }

    private init() {
        updateMonitor()
    }

    func setKatiKatiBindings(_ bindings: [ShortcutAction: ShortcutTrigger]) {
        katikatiBindings = bindings
    }

    func setTrigger(_ newTrigger: ShortcutCheatSheetTrigger) {
        guard newTrigger != trigger else { return }
        trigger = newTrigger
        UserDefaults.standard.set(newTrigger.rawValue, forKey: Self.triggerKey)
        updateMonitor()
    }

    func toggle(pinned: Bool = true) {
        if isVisible {
            hide()
        } else {
            show(pinned: pinned)
        }
    }

    func show(pinned: Bool = false) {
        let front = NSWorkspace.shared.frontmostApplication
        let pid = front?.processIdentifier ?? 0
        targetPID = pid
        appName = front?.localizedName ?? "App"
        appIcon = front?.icon
        isPinned = pinned
        isVisible = true
        searchQuery = ""

        let overlay = self.overlay ?? ShortcutCheatSheetOverlayController(service: self)
        self.overlay = overlay
        overlay.show()

        loadShortcuts(for: pid)
    }

    func hide() {
        holdWork?.cancel()
        holdWork = nil
        isVisible = false
        isPinned = false
        overlay?.hide()
    }

    func activate(_ item: ShortcutCheatSheetItem) {
        guard !item.path.isEmpty, targetPID != 0 else { return }
        let pid = targetPID
        hide()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = AppMenuSearchReader.press(path: item.path, pid: pid)
        }
    }

    func copyMarkdown() {
        let filtered = ShortcutCheatSheetBuilder.filter(
            categories: categories,
            query: searchQuery,
            requiredModifiers: liveModifiers
        )
        let md = ShortcutCheatSheetBuilder.exportMarkdown(appName: appName, categories: filtered)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    private func loadShortcuts(for pid: pid_t) {
        let katikatiItems = currentKatiKatiItems()
        if let cached = cache[pid], Date().timeIntervalSince(cached.at) < 30 {
            categories = ShortcutCheatSheetBuilder.build(entries: cached.entries, katikatiItems: katikatiItems)
            isLoading = false
            return
        }
        isLoading = true
        categories = ShortcutCheatSheetBuilder.build(entries: [], katikatiItems: katikatiItems)
        Task { [weak self] in
            let entries = await Task.detached(priority: .userInitiated) {
                pid != 0 ? AppMenuSearchReader.entries(pid: pid, budget: 1.2) : []
            }.value
            guard let self else { return }
            self.cache[pid] = (Date(), entries)
            guard self.targetPID == pid else { return }
            self.categories = ShortcutCheatSheetBuilder.build(entries: entries, katikatiItems: katikatiItems)
            self.isLoading = false
        }
    }

    private func currentKatiKatiItems() -> [ShortcutCheatSheetItem] {
        return ShortcutAction.allCases.compactMap { action -> ShortcutCheatSheetItem? in
            // The live binding when the store has one, the shipped default otherwise — the sheet
            // must never hide a shortcut the Settings pane would still show.
            let trigger = katikatiBindings[action] ?? action.defaultTrigger
            guard let glyphs = trigger.displayGlyphs else { return nil }
            return ShortcutCheatSheetItem(
                id: "katikati.\(action.rawValue)",
                title: SettingsLayoutPane.shortcutActionName(action),
                subtitle: "KatiKati",
                shortcut: glyphs,
                modifiers: trigger.modifiers,
                category: "KatiKati",
                path: []
            )
        }
    }

    // MARK: - Modifier Trigger Monitor (Double-tap & Hold ⌘ / Hold ⌘)

    private func updateMonitor() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m); localFlagsMonitor = nil }
        guard trigger != .off else { return }

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
            return event
        }
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags
        if isVisible {
            var mods: KeyModifiers = []
            if flags.contains(.shift) { mods.insert(.shift) }
            if flags.contains(.option) { mods.insert(.option) }
            if flags.contains(.control) { mods.insert(.control) }
            liveModifiers = mods
        }

        let cmdNow = flags.contains(.command)
            && !flags.contains(.option)
            && !flags.contains(.control)
            && !flags.contains(.shift)

        if cmdNow && !cmdIsDown {
            cmdIsDown = true
            switch trigger {
            case .off:
                break
            case .doubleTapCommand:
                let now = Date()
                if let last = lastCmdUpAt, now.timeIntervalSince(last) <= 0.32 {
                    lastCmdUpAt = nil
                    scheduleHoldOpen(delay: 0.12)
                }
            case .holdCommand:
                scheduleHoldOpen(delay: 0.55)
            }
        } else if !flags.contains(.command) && cmdIsDown {
            cmdIsDown = false
            holdWork?.cancel()
            holdWork = nil
            lastCmdUpAt = Date()
            if isVisible && !isPinned {
                hide()
            }
        }
    }

    private func scheduleHoldOpen(delay: TimeInterval) {
        holdWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.cmdIsDown, !self.isVisible else { return }
                self.show(pinned: false)
            }
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
