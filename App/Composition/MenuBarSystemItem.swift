import AppKit
import Combine

/// Pass 2 — the menu-bar readout is multi-metric (Stats-style): one status item per enabled
/// metric, each with its own display style, and a click menu with every reading plus the usual
/// shortcuts. Off by default: the items and the 1 s sampler exist only while at least one metric
/// is on, so a user who never enables it pays nothing (the Phase 20c discipline, kept).
@MainActor
final class MenuBarSystemItem: NSObject, NSMenuDelegate {
    /// The master switch; same key the old single CPU/MEM readout used.
    static let enabledKey = MenuBarStatModel.masterEnabledKey

    private let monitor = SystemMonitorController()
    private var items: [MenuBarMetric: NSStatusItem] = [:]
    private var sink: AnyCancellable?
    private var observer: NSObjectProtocol?
    private var lastValues = MenuBarStatValues()

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }
        apply()
    }

    private func isOn(_ metric: MenuBarMetric) -> Bool { MenuBarStatModel.isEnabled(metric) }

    private func style(_ metric: MenuBarMetric) -> MenuBarMetricStyle {
        MenuBarStatModel.style(UserDefaults.standard.string(forKey: MenuBarStatModel.styleKey(metric)), for: metric)
    }

    private func apply() {
        let masterOn = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let wanted = masterOn ? MenuBarMetric.allCases.filter(isOn) : []
        for (metric, item) in items where !wanted.contains(metric) {
            NSStatusBar.system.removeStatusItem(item)
            items[metric] = nil
        }
        for metric in wanted where items[metric] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            items[metric] = item
        }
        if items.isEmpty {
            sink = nil
            monitor.release()
        } else if sink == nil {
            monitor.acquire()
            sink = monitor.$snapshot.sink { [weak self] snapshot in self?.render(snapshot) }
        }
        render(monitor.snapshot)
    }

    private func render(_ snapshot: SystemSnapshot) {
        let values = MenuBarStatValues(
            cpu: snapshot.cpu,
            memory: snapshot.memory.fraction,
            gpu: SystemMonitorSampler.gpu(),
            storageUsed: snapshot.disk.usedFraction,
            storageFreeBytes: Double(snapshot.disk.free),
            storageTotalBytes: Double(snapshot.disk.total),
            battery: SystemMonitorSampler.battery(),
            down: snapshot.down,
            up: snapshot.up)
        lastValues = values
        for (metric, item) in items {
            let style = style(metric)
            let text = MenuBarStatModel.statusText(metric: metric, style: style, values: values)
            item.button?.title = text
            item.button?.image = image(metric: metric, style: style, values: values)
            item.button?.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
            item.button?.toolTip = "\(Self.name(metric)) \(MenuBarStatModel.menuRowText(metric: metric, values: values))"
        }
    }

    private func image(metric: MenuBarMetric, style: MenuBarMetricStyle, values: MenuBarStatValues) -> NSImage? {
        switch style {
        case .barGraph:
            return Self.barImage(MenuBarStatModel.imageFraction(metric: metric, values: values))
        case .pieChart:
            return Self.pieImage(MenuBarStatModel.imageFraction(metric: metric, values: values))
        case .iconOnly:
            return NSImage(systemSymbolName: MenuBarStatModel.batterySymbol(values.battery), accessibilityDescription: nil)
        case .percentage, .available, .used:
            return NSImage(systemSymbolName: MenuBarStatModel.symbolName(metric: metric), accessibilityDescription: nil)
        }
    }

    // MARK: - Click menu (rebuilt on every open, so the readings are never stale)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for metric in MenuBarMetric.allCases {
            let row = NSMenuItem(
                title: "\(Self.name(metric))  \(MenuBarStatModel.menuRowText(metric: metric, values: lastValues))",
                action: nil, keyEquivalent: "")
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "Open Settings…"), action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let activity = NSMenuItem(title: String(localized: "Open Activity Monitor"), action: #selector(openActivityMonitor), keyEquivalent: "")
        activity.target = self
        menu.addItem(activity)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit KatiKati"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        (NSApp.delegate as? AppDelegate)?.openSettings(nil)
    }

    @objc private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func name(_ metric: MenuBarMetric) -> String { MenuBarStatModel.displayName(metric) }

    // MARK: - Template images for the drawing styles (tint to the menu bar automatically)

    private static func barImage(_ fraction: Double?) -> NSImage {
        let f = fraction ?? 0
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor(white: 1, alpha: 0.3).setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 5.5, width: 14, height: 5), xRadius: 2.5, yRadius: 2.5).fill()
            NSColor(white: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 5.5, width: max(1, 14 * f), height: 5), xRadius: 2.5, yRadius: 2.5).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func pieImage(_ fraction: Double?) -> NSImage {
        let f = fraction ?? 0
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor(white: 1, alpha: 0.3).setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12)).fill()
            if f > 0 {
                let wedge = NSBezierPath()
                wedge.move(to: NSPoint(x: 8, y: 8))
                wedge.appendArc(withCenter: NSPoint(x: 8, y: 8), radius: 6, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
                wedge.close()
                NSColor(white: 1, alpha: 1).setFill()
                wedge.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
