import AppKit
import SwiftUI

// MARK: - Native right-click menu infrastructure
//
// The chips use a hand-built AppKit `NSMenu` instead of SwiftUI's `.contextMenu`,
// so the「退出 App」/「强制退出」pair can use AppKit's native *alternate item*
// (`isAlternate` + Option modifier): with the menu already open, holding Option
// swaps the visible item live — exactly like the system Dock. SwiftUI's
// `.contextMenu` is a static snapshot once open and cannot do this.

/// An `NSMenuItem` that runs a closure when picked (AppKit needs target/action).
final class ClosureMenuItem: NSMenuItem {
    let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}

/// A transparent overlay NSView that provides a native menu on right-click /
/// control-click, while passing every other click through to the SwiftUI chip
/// beneath it (so tap-to-activate and drag-reorder are unaffected).
final class MenuHostNSView: NSView {
    var builder: (() -> NSMenu)?
    /// 由外部自己负责弹出的通道（任务条 / 胶囊右键走这条）。设了它就不再走 `builder`：
    /// 钨极菜单是 `StatusMenuController` 持有的**同一个** `NSMenu` 实例（里面的滑块是有状态的
    /// 自绘 NSView，不能克隆），弹出时机也归它管，所以不把菜单对象漏出来。
    var popUpHandler: ((NSEvent, NSView) -> Void)?
    /// 命中过滤（屏幕坐标）。任务条底板用它把响应范围收窄到"两端空白 + 分割线"，
    /// 别的调用点不设，行为与从前完全一致。
    var shouldClaim: ((CGPoint) -> Bool)?

    // Only claim right-click / control-click; return nil otherwise so the click
    // falls through to the SwiftUI content below this overlay.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil, let e = NSApp.currentEvent else { return nil }
        if let shouldClaim, !shouldClaim(NSEvent.mouseLocation) { return nil }
        switch e.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return self
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return e.modifierFlags.contains(.control) ? self : nil
        default:
            return nil
        }
    }

    override func rightMouseDown(with event: NSEvent) { popUp(event) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { popUp(event) }
        else { super.mouseDown(with: event) }
    }

    private func popUp(_ event: NSEvent) {
        if let popUpHandler {
            popUpHandler(event, self)
            return
        }
        guard let menu = builder?(), !menu.items.isEmpty else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

struct NativeMenuHost: NSViewRepresentable {
    var builder: (() -> NSMenu)?
    var popUpHandler: ((NSEvent, NSView) -> Void)?
    var shouldClaim: ((CGPoint) -> Bool)?

    init(builder: @escaping () -> NSMenu) {
        self.builder = builder
    }

    init(
        popUpHandler: @escaping (NSEvent, NSView) -> Void,
        shouldClaim: ((CGPoint) -> Bool)? = nil
    ) {
        self.popUpHandler = popUpHandler
        self.shouldClaim = shouldClaim
    }

    func makeNSView(context: Context) -> MenuHostNSView {
        let v = MenuHostNSView()
        v.builder = builder
        v.popUpHandler = popUpHandler
        v.shouldClaim = shouldClaim
        return v
    }
    func updateNSView(_ v: MenuHostNSView, context: Context) {
        // keep the closures capturing current SwiftUI state
        v.builder = builder
        v.popUpHandler = popUpHandler
        v.shouldClaim = shouldClaim
    }
}

extension View {
    /// Attach a native AppKit right-click menu, rebuilt fresh on each open.
    func nativeContextMenu(_ builder: @escaping () -> NSMenu) -> some View {
        overlay(NativeMenuHost(builder: builder))
    }

    /// Right-click menu that floats **above** the dock (the chip panel) instead of covering it. Falls back
    /// to the native `NSMenu` where no presenter is injected (drawer, drag snapshots).
    func floatingContextMenu(shouldClaim: ((CGPoint) -> Bool)? = nil,
                              _ builder: @escaping () -> NSMenu) -> some View {
        overlay(FloatingMenuHost(builder: builder, shouldClaim: shouldClaim))
    }
}

// MARK: - Shared menu fragments

enum AppMenuBuilder {

    /// Render one membership descriptor as a native AppKit menu item. AppKit owns
    /// the checkmark; SwiftUI/store state is captured when the menu is rebuilt.
    static func membershipItem(_ descriptor: LauncherMembershipItem) -> NSMenuItem {
        let item = ClosureMenuItem(descriptor.label, handler: descriptor.action)
        if let isChecked = descriptor.isChecked {
            item.state = isChecked ? .on : .off
        }
        return item
    }

    /// Append「退出 App」plus, for non-self apps, the Option-alternate「强制退出」.
    /// The two are an alternate pair: same (empty) key equivalent, the second
    /// `isAlternate` with the Option modifier → live swap while the menu is open.
    static func appendQuitItems(
        to menu: NSMenu,
        bundleID: String?,
        onForceQuit: (() -> Void)? = nil,
        onQuit: @escaping () -> Void
    ) {
        let quit = ClosureMenuItem(String(localized: "Quit App"), handler: onQuit)
        quit.keyEquivalentModifierMask = []
        menu.addItem(quit)

        guard let bid = bundleID, bid != Bundle.main.bundleIdentifier else { return }
        let force = ClosureMenuItem(String(localized: "Force Quit")) {
            if let onForceQuit {
                onForceQuit()
            } else {
                NSRunningApplication
                    .runningApplications(withBundleIdentifier: bid)
                    .first?
                    .forceTerminate()
            }
        }
        force.keyEquivalentModifierMask = [.option]
        force.isAlternate = true
        menu.addItem(force)
    }

    /// Dock 式窗口列表（仅应用级图标；具体窗口卡不列）：✓ = 前台窗，◇ = 已最小化，
    /// 点击 = activate（最小化则还原）。条目来自纯 `WindowListMenuPlan`（只读快照，
    /// 菜单路径上不做任何 AX）。空列表什么都不加。
    static func appendWindowList(
        to menu: NSMenu,
        entries: [WindowMenuEntry],
        activate: @escaping (String) -> Void
    ) {
        guard !entries.isEmpty else { return }
        for entry in entries {
            let item = ClosureMenuItem(entry.title) { activate(entry.actionWindowID) }
            switch entry.marker {
            case .none:
                break
            case .front:
                item.state = .on
            case .minimized:
                // ◇：原生 Dock 的最小化标记。SF Symbol「diamond」macOS 12 就有；
                // 万一取不到（理论防御）退回文字前缀，别让标记静默消失。
                if let diamond = NSImage(
                    systemSymbolName: "diamond",
                    accessibilityDescription: String(localized: "Minimized")
                ) {
                    item.state = .on
                    item.onStateImage = diamond
                } else {
                    item.title = "◇ " + entry.title
                }
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    /// 「最常用的文件」区（2026-08-24 由「最近使用的文件」改排序而来），inline at the menu top.
    /// 候选 = 系统最近列表（读 20 条当排序池）∪ 钨极自己的计数账本；次数降序、同次数看最近，
    /// 没计过数的按系统最近序垫底（刚升级时与原来的「最近」一致）。顺手把本次榜首交给
    /// `DocumentUsageStore` 采样（菜单打开就是一次兜底重采样）。Opens each doc in its
    /// owning app. Adds nothing when there's no readable data.
    static func appendRecentDocuments(to menu: NSMenu, bundleID: String?) {
        guard let bid = bundleID else { return }
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
        let recentPaths = RecentDocumentsReader.recentDocuments(for: bid, maxCount: 20).map(\.path)
        // 菜单只在主线程构建（NSMenu 本来也只能在主线程用），但本类型是非隔离的，
        // 编译器看不出来——assumeIsolated 把这个事实变成运行时断言。
        let ranked = MainActor.assumeIsolated { () -> [String] in
            let usage = DocumentUsageStore.shared
            usage.noteRecentSample(bundleID: bid, topPath: recentPaths.first)
            return usage.ranked(bundleID: bid, recentPaths: recentPaths)
        }
        let entries = ranked.map { path in
            RecentMenuEntry(title: (path as NSString).lastPathComponent, url: URL(fileURLWithPath: path))
        }
        appendRecentItems(to: menu, title: String(localized: "Most Used Files"), entries: entries) { url in
            MainActor.assumeIsolated {
                DocumentUsageStore.shared.recordOpen(bundleID: bid, path: url.path)
            }
            openRecent(url, appURL: appURL)
        }
    }

    /// Top recent-folders section for the Finder chip, inline. Opens each folder in Finder.
    static func appendFinderRecentFolders(to menu: NSMenu) {
        appendRecentItems(to: menu, title: String(localized: "Recent Folders"),
                          entries: RecentDocumentsReader.recentFinderFolders()) { NSWorkspace.shared.open($0) }
    }

    /// Shared builder: a grayed section header + the file/folder rows (16pt icon) added
    /// inline to `menu` (no submenu), then a separator.
    private static func appendRecentItems(to menu: NSMenu, title: String,
                                          entries: [RecentMenuEntry], open: @escaping (URL) -> Void) {
        guard !entries.isEmpty else { return }
        // Grayed, non-clickable section header (action == nil auto-disables it; macOS 12
        // compatible — not the macOS 14 NSMenuItem.sectionHeader).
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for entry in entries {
            let it = ClosureMenuItem(entry.title) { open(entry.url) }
            // copy() before resizing: icon(forFile:) returns a shared cached NSImage;
            // mutating its size in place would shrink it everywhere else too.
            let icon = NSWorkspace.shared.icon(forFile: entry.url.path).copy() as? NSImage
            icon?.size = NSSize(width: 16, height: 16)
            it.image = icon
            menu.addItem(it)
        }
        menu.addItem(.separator())
    }

    /// Open a recent doc in its owning app (matches the native Dock); fall back to
    /// the default app if the owner can't be resolved or refuses to open it.
    static func openRecent(_ url: URL, appURL: URL?) {
        guard let appURL else { NSWorkspace.shared.open(url); return }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init()) { _, error in
            if error != nil { DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
        }
    }

    /// Finder-only shortcuts at the top of the Finder chip menu, plus a separator.
    static func appendFinderItems(to menu: NSMenu) {
        menu.addItem(ClosureMenuItem(String(localized: "Go to Folder…")) { triggerFinderShortcut(goToFolder: true) })
        menu.addItem(ClosureMenuItem(String(localized: "Connect to Server…")) { triggerFinderShortcut(goToFolder: false) })
        menu.addItem(.separator())
    }

    /// The app's own "new window / new tab" rows, in its words — the macOS Dock's own menu, as far as
    /// one app may read another's. The AX read happens here, at right-click time, once: a normal File
    /// menu answers in milliseconds and the reader's 0.35 s timeout bounds a busy one. Returns whether
    /// anything was added, so the caller can keep its generic New Window as the fallback.
    @discardableResult
    static func appendAppNewItems(to menu: NSMenu, bundleID: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        let rows = AppMenuBarReader.rows(pid: app.processIdentifier)
        for row in rows {
            menu.addItem(ClosureMenuItem(row.title) { AppMenuBarReader.press(row) })
        }
        return !rows.isEmpty
    }

    // Key codes from HIToolbox/Events.h — defined locally to avoid a Carbon dependency
    private static let keyG: CGKeyCode = 0x05  // kVK_ANSI_G
    private static let keyK: CGKeyCode = 0x28  // kVK_ANSI_K

    private static func triggerFinderShortcut(goToFolder: Bool) {
        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder").first else { return }
        finder.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let keyCode = goToFolder ? keyG : keyK
            let flags: CGEventFlags = goToFolder ? [.maskCommand, .maskShift] : [.maskCommand]
            for keyDown in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: keyDown)
                e?.flags = flags
                e?.postToPid(finder.processIdentifier)
            }
        }
    }

    /// Appends an `App Groups` submenu so any running/pinned/Launcher app can join, leave, or start a Dock App Group.
    @MainActor
    static func appendAppGroupMenu(to menu: NSMenu, bundleID: String?) {
        let groupStore = DockAppGroupStore.shared
        guard groupStore.isEnabled, let bid = bundleID, !bid.isEmpty else { return }
        let submenu = NSMenu()
        for group in groupStore.groups {
            let member = group.appIDs.contains(bid)
            let item = ClosureMenuItem(group.name) {
                if member { groupStore.removeApp(bid, from: group.id) } else { groupStore.addApp(bid, to: group.id) }
            }
            item.state = member ? .on : .off
            submenu.addItem(item)
        }
        if !groupStore.groups.isEmpty { submenu.addItem(.separator()) }
        submenu.addItem(ClosureMenuItem(String(localized: "New App Group")) {
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
            let rawCategory = appURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String } ?? ""
            let category = DockAppGroups.categoryDisplayName(for: rawCategory)
            let title = category.isEmpty ? AppDisplayNameResolver.displayName(for: bid) : category
            groupStore.createGroup(name: title, appIDs: [bid])
        })
        let top = NSMenuItem(title: String(localized: "App Groups"), action: nil, keyEquivalent: "")
        top.submenu = submenu
        menu.addItem(top)
    }
}


/// Environment hook the panel coordinator fills in: show this menu as the floating chip panel above `anchor`
/// (screen coordinates, y up).
typealias ChipMenuPresenter = (NSMenu, CGRect) -> Void

private struct ChipMenuPresenterKey: EnvironmentKey {
    static let defaultValue: ChipMenuPresenter? = nil
}

extension EnvironmentValues {
    var chipMenuPresenter: ChipMenuPresenter? {
        get { self[ChipMenuPresenterKey.self] }
        set { self[ChipMenuPresenterKey.self] = newValue }
    }
}

extension NSMenu {
    /// A custom-view row (the hub-style header, the taskbar-size slider) has no text row to become,
    /// so the floating chip panel cannot draw it — such menus must open natively.
    var hasViewItem: Bool { items.contains { $0.view != nil } }
}

struct FloatingMenuHost: View {
    let builder: () -> NSMenu
    /// Optional claim filter in screen coordinates (bottom-left, `NSEvent.mouseLocation`): a section
    /// host uses it to yield to the chips it hosts. Nil claims everywhere, as before.
    var shouldClaim: ((CGPoint) -> Bool)?
    @Environment(\.chipMenuPresenter) private var presenter

    var body: some View {
        NativeMenuHost(popUpHandler: { event, view in
            let menu = builder()
            guard !menu.items.isEmpty else { return }
            if let presenter, let window = view.window, !menu.hasViewItem {
                let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
                presenter(menu, rect)
            } else {
                NSMenu.popUpContextMenu(menu, with: event, for: view)
            }
        }, shouldClaim: shouldClaim)
    }
}


// MARK: - Strip widget menu (Phase 10a-4)

/// Right-click menu for a strip widget: size presets, hide, and one-step reordering. Shown through the
/// floating chip panel (`floatingContextMenu`), where the Size submenu becomes a header plus indented rows.
enum WidgetMenuBuilder {
    /// Menu labels for the weather presets. The Settings picker shows `WeatherChipPreset.title`
    /// (short, untranslated); these are the localized menu names, kept here so the catalog keys stay
    /// the ones the app already shipped.
    static func weatherPresetMenuTitle(_ preset: WeatherChipPreset) -> String {
        switch preset {
        case .modern: return String(localized: "Modern")
        case .ipad: return String(localized: "iPad Sky Card")
        case .detailedForecast: return String(localized: "Detailed Forecast")
        case .classicPill: return String(localized: "Classic Pill")
        case .detailedGlass: return String(localized: "Glass Forecast")
        case .classicGlassPill: return String(localized: "Glass Pill")
        }
    }

    @MainActor
    static func menu(for section: BarSection, store: AppSettingsStore, isVertical: Bool = false) -> NSMenu {
        let menu = NSMenu()
        guard section != .apps else { return menu }
        let layout = store.widgetLayout
        let instance = layout.instance(for: section)

        var status: [String] = []
        if section.supportsWidgetSizes { status.append(sizeTitle(instance.size)) }
        if instance.stack != nil { status.append(String(localized: "Smart Stack")) }
        menu.addItem(DockMenuChrome.header(
            icon: nil,
            symbol: symbol(for: section),
            title: section.title,
            status: status.isEmpty ? nil : status.joined(separator: " · "),
            tiles: [
                .init(symbol: "gearshape", caption: String(localized: "Settings")) {
                    DispatchQueue.main.async {
                        AppDelegate.shared?.openSettings(selecting: section == .weather ? .weather : .dockItems)
                    }
                },
                .init(symbol: "slider.horizontal.3",
                      caption: String(localized: WidgetEditMode.shared.isEditing ? "Done" : "Edit")) {
                    WidgetEditMode.shared.toggle()
                },
                .init(symbol: "eye.slash", caption: String(localized: "Hide")) {
                    store.setWidgetLayout(store.widgetLayout.updating(section) { $0.isVisible = false })
                },
            ],
            menu: menu
        ))
        menu.addItem(.separator())

        if section.supportsWidgetSizes {
            MenuChrome.section(String(localized: "Size"), symbol: "rectangle.3.group", in: menu)
            for size in [WidgetSize.small, WidgetSize.medium, WidgetSize.large] {
                let row = MenuChrome.action(sizeTitle(size), symbol: sizeSymbol(size), in: menu) {
                    store.setWidgetSize(size, for: section)
                }
                row.state = size == instance.size ? .on : .off
            }
        }

        if section == .clock {
            MenuChrome.submenu(String(localized: "Clock Style"), symbol: "clock", in: menu) { sub in
                let current = UserDefaults.standard.string(forKey: "com.katikati.clock.preset") ?? ClockPreset.stackedCard.rawValue
                for (preset, title) in [(ClockPreset.stackedCard, String(localized: "Stacked")),
                                        (ClockPreset.minimal, String(localized: "Minimal")),
                                        (ClockPreset.modernMac, String(localized: "Modern")),
                                        (.pixelRetro, String(localized: "Pixel")),
                                        (.flipTiles, String(localized: "Flip clock"))] {
                    let item = ClosureMenuItem(title) { UserDefaults.standard.set(preset.rawValue, forKey: "com.katikati.clock.preset") }
                    item.state = preset.rawValue == current ? .on : .off
                    sub.addItem(item)
                }
            }
        }
        if section == .weather {
            MenuChrome.submenu(String(localized: "Temperature Unit"), symbol: "thermometer.medium", in: menu) { sub in
                let current = UserDefaults.standard.string(forKey: WeatherUnits.temperatureKey) ?? TemperatureUnit.celsius.rawValue
                for (unit, title) in [(TemperatureUnit.celsius, "°C"), (.fahrenheit, "°F")] {
                    let item = ClosureMenuItem(title) { UserDefaults.standard.set(unit.rawValue, forKey: WeatherUnits.temperatureKey) }
                    item.state = unit.rawValue == current ? .on : .off
                    sub.addItem(item)
                }
            }
            MenuChrome.submenu(String(localized: "Weather Style"), symbol: "cloud.sun", in: menu) { sub in
                let currentPreset = UserDefaults.standard.string(forKey: "com.katikati.weather.chipPreset") ?? WeatherChipPreset.modern.rawValue
                for preset in WeatherChipPreset.pickerCases(current: WeatherChipPreset(rawValue: currentPreset) ?? .modern) {
                    let item = ClosureMenuItem(Self.weatherPresetMenuTitle(preset)) {
                        UserDefaults.standard.set(preset.rawValue, forKey: "com.katikati.weather.chipPreset")
                    }
                    item.state = preset.rawValue == currentPreset ? .on : .off
                    sub.addItem(item)
                }
            }
        }
        if section == .widgets {
            MenuChrome.submenu(String(localized: "FAB Style"), symbol: "dial.medium", in: menu) { sub in
                let current = UserDefaults.standard.string(forKey: "com.katikati.widgets.fabStyle") ?? "gauge"
                for (key, title) in [("gauge", String(localized: "Dynamic Gauge")),
                                     ("classic", String(localized: "Classic Glyph"))] {
                    let item = ClosureMenuItem(title) { UserDefaults.standard.set(key, forKey: "com.katikati.widgets.fabStyle") }
                    item.state = key == current ? .on : .off
                    sub.addItem(item)
                }
            }
        }
        if section == .media {
            MenuChrome.submenu(String(localized: "Media Player Style"), symbol: "music.note", in: menu) { sub in
                let current = UserDefaults.standard.string(forKey: "com.katikati.media.preset") ?? NowPlayingPreset.accentCard.rawValue
                for (preset, title) in [(NowPlayingPreset.accentCard, "Accent Wash Card"),
                                        (NowPlayingPreset.graphiteCard, String(localized: "Graphite Card")),
                                        (NowPlayingPreset.expandedCard, String(localized: "Expanded Card")),
                                        (NowPlayingPreset.miniChip, String(localized: "Mini Chip"))] {
                    let item = ClosureMenuItem(title) { UserDefaults.standard.set(preset.rawValue, forKey: "com.katikati.media.preset") }
                    item.state = preset.rawValue == current ? .on : .off
                    sub.addItem(item)
                }
            }
        }

        if section.supportsWidgetSizes {
            let stacked = instance.stack != nil
            MenuChrome.section(String(localized: "Layout"), symbol: "square.stack.3d.up", in: menu)
            let stackRow = MenuChrome.action(String(localized: "Smart Stack"), symbol: "square.stack.3d.up", in: menu) {
                store.setWidgetLayout(store.widgetLayout.updating(section) {
                    $0.stack = stacked ? nil : StackRelevance.defaultMembers
                })
            }
            stackRow.state = stacked ? .on : .off
            if StackRelevance.defaultMembers.contains(section) {
                let glance = StackRelevance.glanceMembers
                let members = instance.stack ?? []
                let glanceOn = glance.allSatisfy(members.contains)
                let glanceRow = MenuChrome.action(String(localized: "Calendar, System & Devices in Stack"),
                                                  symbol: "checklist", in: menu) {
                    store.setWidgetLayout(store.widgetLayout.updating(section) {
                        let base = $0.stack ?? [section]
                        $0.stack = glanceOn ? base.filter { !glance.contains($0) } : base + glance.filter { !base.contains($0) }
                        if $0.stack?.count ?? 0 < 2 { $0.stack = nil }
                    })
                }
                glanceRow.state = glanceOn ? .on : .off
            }
            if stacked, let members = instance.stack {
                MenuChrome.action(String(localized: "Show Next in Stack"), symbol: "forward.end", in: menu) {
                    SmartStackState.shared.showNext(host: section, members: members)
                }
            }
        }

        if let index = layout.order.firstIndex(of: section), layout.order.count > 1 {
            MenuChrome.section(String(localized: "Position"), symbol: "arrow.left.and.right", in: menu)
            if index > 0 {
                MenuChrome.action(isVertical ? String(localized: "Move Up") : String(localized: "Move Left"),
                                  symbol: isVertical ? "arrow.up" : "arrow.left", in: menu) {
                    store.setWidgetLayout(store.widgetLayout.moving(from: IndexSet(integer: index), to: index - 1))
                }
            }
            if index < layout.order.count - 1 {
                MenuChrome.action(isVertical ? String(localized: "Move Down") : String(localized: "Move Right"),
                                  symbol: isVertical ? "arrow.down" : "arrow.right", in: menu) {
                    store.setWidgetLayout(store.widgetLayout.moving(from: IndexSet(integer: index), to: index + 2))
                }
            }
        }

        menu.addItem(.separator())
        MenuChrome.action(String(localized: "Widget Settings…"), symbol: "gearshape", in: menu) {
            DispatchQueue.main.async {
                AppDelegate.shared?.openSettings(selecting: section == .weather ? .weather : .dockItems)
            }
        }
        MenuChrome.submenu(String(localized: "Apply Preset"), symbol: "wand.and.stars", in: menu) { sub in
            for preset in WidgetPresets.builtIns { sub.addItem(ClosureMenuItem(preset.localizedTitle) { store.applyWidgetPreset(preset) }) }
            for preset in store.userWidgetPresets { sub.addItem(ClosureMenuItem(preset.name) { store.applyWidgetPreset(preset) }) }
        }
        MenuChrome.action(WidgetEditMode.shared.isEditing ? String(localized: "Done Editing Widgets") : String(localized: "Edit Widgets"),
                          symbol: "slider.horizontal.3", in: menu) {
            WidgetEditMode.shared.toggle()
        }
        MenuChrome.action(String(localized: "Hide"), symbol: "eye.slash", in: menu) {
            store.setWidgetLayout(store.widgetLayout.updating(section) { $0.isVisible = false })
        }
        return menu
    }

    private static func sizeTitle(_ size: WidgetSize) -> String {
        switch size {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        default: return String(localized: "Large")
        }
    }

    private static func sizeSymbol(_ size: WidgetSize) -> String {
        switch size {
        case .small: return "rectangle.portrait"
        case .medium: return "rectangle.grid.1x2"
        default: return "rectangle.grid.2x2"
        }
    }

    private static func symbol(for section: BarSection) -> String {
        switch section {
        case .weather: return "cloud.sun"
        case .clock: return "clock"
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .system: return "gauge.medium"
        case .devices: return "airpods"
        case .drives: return "externaldrive"
        case .dictionary: return "text.book.closed"
        case .terminal: return "terminal"
        case .ai: return "sparkles"
        case .widgets: return "square.grid.2x2"
        case .utilities: return "wrench.and.screwdriver"
        case .launcher: return "square.grid.3x3"
        case .apps: return "square.grid.2x2"
        }
    }
}


// MARK: - Live Island chip menu (Phase 10c-1b)

/// Full controls for the dock Live Island chip, shown through the floating chip panel (right-click on the
/// chip). Sections are plain headers + rows, so the panel bridge renders them as it does every dock menu.
enum LiveIslandMenuBuilder {
    @MainActor
    static func menu(feed: LiveActivityFeed, keepAwakeOn: Bool, toggleKeepAwake: @escaping () -> Void) -> NSMenu {
        let services = ProductivityServices.shared
        let menu = NSMenu()
        func header(_ title: String) {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }

        header(String(localized: "Focus"))
        menu.addItem(ClosureMenuItem(String(localized: "Start / Pause")) { services.focus.toggle() })
        menu.addItem(ClosureMenuItem(String(localized: "Skip")) { services.focus.skip() })
        menu.addItem(ClosureMenuItem(String(localized: "Reset")) { services.focus.reset() })

        header(String(localized: "Timer"))
        for minutes in [5, 15, 25, 60] {
            menu.addItem(ClosureMenuItem("\(minutes)m") {
                services.timer.set(seconds: minutes * 60)
                services.timer.toggle()
            })
        }
        menu.addItem(ClosureMenuItem(String(localized: "Stop")) { services.timer.reset() })

        header(String(localized: "Keep Awake"))
        let awake = ClosureMenuItem(String(localized: "Keep Awake")) { toggleKeepAwake() }
        awake.state = keepAwakeOn ? .on : .off
        menu.addItem(awake)

        if case .music = feed.activity.content {
            header(String(localized: "Now Playing"))
            menu.addItem(ClosureMenuItem(String(localized: "Play / Pause")) { feed.togglePlayPause() })
            menu.addItem(ClosureMenuItem(String(localized: "Next Track")) { feed.nextTrack() })
            menu.addItem(ClosureMenuItem(String(localized: "Previous Track")) { feed.previousTrack() })
        }
        return menu
    }
}

enum DockUtilityMenuBuilder {
    @MainActor
    static func menu(
        for kind: DockUtilityKind,
        store: AppSettingsStore,
        downloadsPath: String? = nil,
        onOpen: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        switch kind {
        case .screenshots:
            menu.addItem(ClosureMenuItem(String(localized: "Capture Area")) { CaptureController.captureAreaToClipboard() })
            menu.addItem(ClosureMenuItem(String(localized: "Open Screenshots")) { onOpen() })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(String(localized: "Hide")) { store.setDockUtilityVisible(.screenshots, false) })
        case .clipboard:
            let monitor = ProductivityServices.shared.clipboard
            if let latest = monitor.history.displayOrder.first {
                menu.addItem(ClosureMenuItem(String(localized: "Paste Latest Plain")) { monitor.pastePlain(latest) })
                menu.addItem(ClosureMenuItem(String(localized: "Clear Unpinned")) { monitor.clearAll(keepingPinned: true) })
                menu.addItem(.separator())
            }
            menu.addItem(ClosureMenuItem(String(localized: "Open Clipboard")) { onOpen() })
            menu.addItem(ClosureMenuItem(String(localized: "Hide")) { store.setDockUtilityVisible(.clipboard, false) })
        case .dictionary:
            menu.addItem(ClosureMenuItem(String(localized: "Open Dictionary")) { onOpen() })
            menu.addItem(ClosureMenuItem(String(localized: "Hide")) { store.setDockUtilityVisible(.dictionary, false) })
        case .terminal:
            menu.addItem(ClosureMenuItem(String(localized: "Toggle Terminal")) { onOpen() })
            menu.addItem(ClosureMenuItem(String(localized: "Hide Terminal")) { store.setDockUtilityVisible(.terminal, false) })
        case .downloads:
            if let path = downloadsPath {
                menu.addItem(ClosureMenuItem(String(localized: "Open in Finder")) {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                })
            }
            menu.addItem(ClosureMenuItem(String(localized: "Hide")) { store.setDockUtilityVisible(.downloads, false) })
        case .drawer, .trash:
            break
        }
        return menu
    }
}

// MARK: - Dock menu chrome

/// The header's fixed width. Menu rows are 300 pt wide, so this keeps a narrow inset inside the
/// highlighted row while giving each of the four tiles room for labels like “Control Center”.
private let dockMenuHeaderWidth: CGFloat = 288

/// The visual header at the top of a Dock right-click menu: the same grammar as the Menu Bar hub —
/// a 26 pt icon well, a 12.5 pt semibold name, a quiet status pill, and four action wells. It is a
/// hosted SwiftUI view so the hub's type ramp and radii are reused rather than restyled; building
/// it costs one hosting view, with no timers, readers, AX calls or disk walks on the open path.
@MainActor
enum DockMenuChrome {
    struct Tile {
        let symbol: String
        let caption: String
        let action: () -> Void
    }

    static func header(icon: NSImage?, symbol: String? = nil, title: String, status: String?, tiles: [Tile], menu: NSMenu) -> NSMenuItem {
        let host = NSHostingView(rootView: DockMenuHeaderView(icon: icon, symbol: symbol, title: title, status: status, tiles: tiles, menu: menu))
        host.frame = NSRect(x: 0, y: 0, width: dockMenuHeaderWidth, height: 94)
        let item = NSMenuItem()
        item.view = host
        return item
    }
}

extension DockMenuChrome {
    /// The header every Dock surface opens with — the strip's empty area, app chips, pinned folders
    /// and the trash chip. Icon well, surface name, the strip's placement and hide mode, then the four
    /// destinations. Reads only `store` properties and cached images: no readers, timers, AX or disk
    /// work, so the menu still opens on the right-click event.
    @MainActor
    static func dockHeader(
        icon: NSImage?,
        title: String,
        store: AppSettingsStore,
        menu: NSMenu
    ) -> NSMenuItem {
        let tiles = DockMenuModel.stripTiles()
        let placement: String
        switch DockMenuModel.stripPlacementToken(store.stripPlacementMap.global) {
        case "Left": placement = String(localized: "Left")
        case "Right": placement = String(localized: "Right")
        default: placement = String(localized: "Bottom")
        }
        let hiding = store.edgeAutoHideEnabled
            ? String(localized: "Auto-Hide")
            : String(localized: "Always Visible")
        return header(
            icon: icon,
            title: title,
            status: "\(placement) · \(hiding)",
            tiles: [
                .init(symbol: tiles[0].symbol, caption: String(localized: "Settings")) {
                    // The menu is still tracking while the tile runs; open after it has closed so
                    // Settings comes up over the desktop, not under a lingering menu.
                    DispatchQueue.main.async { AppDelegate.shared?.openSettings(nil) }
                },
                .init(symbol: tiles[1].symbol, caption: String(localized: "Control Center")) {
                    DispatchQueue.main.async { AppDelegate.shared?.toggleControlCenter() }
                },
                .init(symbol: tiles[2].symbol, caption: String(localized: "Auto-Hide")) {
                    store.toggleEdgeAutoHideMode()
                },
                .init(symbol: tiles[3].symbol, caption: String(localized: "Position")) {
                    DispatchQueue.main.async { AppDelegate.shared?.openSettings(selecting: .dockItems) }
                },
            ],
            menu: menu
        )
    }

    /// The strip's empty-area right-click wears the Dock itself in the icon well.
    @MainActor
    static func stripHeader(store: AppSettingsStore, menu: NSMenu) -> NSMenuItem {
        dockHeader(
            icon: NSApp.applicationIconImage,
            title: String(localized: "Taskbar"),
            store: store,
            menu: menu
        )
    }
}

/// The small grammar shared by every modernised context menu: 15 pt template symbols on rows,
/// a quiet symbol + caption section label, and submenus that keep the same icon language.
@MainActor
enum MenuChrome {
    static func icon(_ name: String, pointSize: CGFloat = 11.5) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.size = NSSize(width: 15, height: 15)
        image?.isTemplate = true
        return image
    }

    /// A grayed, non-clickable section label with a leading symbol. Adds the separator before itself
    /// when the menu already has rows, so callers never stack two rules.
    static func section(_ title: String, symbol: String, in menu: NSMenu) {
        if let last = menu.items.last, !last.isSeparatorItem { menu.addItem(.separator()) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = icon(symbol)
        item.isEnabled = false
        menu.addItem(item)
    }

    @discardableResult
    static func action(
        _ title: String,
        symbol: String? = nil,
        in menu: NSMenu,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let item = ClosureMenuItem(title, handler: handler)
        if let symbol { item.image = icon(symbol) }
        menu.addItem(item)
        return item
    }

    @discardableResult
    static func submenu(
        _ title: String,
        symbol: String,
        in menu: NSMenu,
        build: (NSMenu) -> Void
    ) -> NSMenuItem {
        let sub = NSMenu(title: title)
        build(sub)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = icon(symbol)
        item.submenu = sub
        menu.addItem(item)
        return item
    }
}

private struct DockMenuHeaderView: View {
    let icon: NSImage?
    /// SF Symbol used when the surface has no app icon to show (widgets, utilities).
    let symbol: String?
    let title: String
    let status: String?
    let tiles: [DockMenuChrome.Tile]
    let menu: NSMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Group {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                    } else if let icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "app.dashed").font(.system(size: 15, weight: .medium))
                    }
                }
                .frame(width: 26, height: 26)
                Text(verbatim: title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let status {
                    Text(verbatim: status)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.primary.opacity(0.09)))
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    Button {
                        tile.action()
                        DispatchQueue.main.async { menu.cancelTracking() }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tile.symbol).font(.system(size: 13, weight: .semibold)).frame(height: 17)
                            Text(verbatim: tile.caption).font(.system(size: 9.5, weight: .medium))
                                .lineLimit(1).minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(width: dockMenuHeaderWidth, height: 94)
    }
}
