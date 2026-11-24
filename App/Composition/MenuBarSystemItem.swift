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

    private let monitor = SystemMonitorController.shared
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
            HoverTrace.statusItem(site: "menuBarMetric:\(metric.rawValue)", length: item.length, square: false,
                                  title: item.button?.title ?? "", image: nil)
            item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            items[metric] = item
        }
        if items.isEmpty {
            if sink != nil {
                sink = nil
                monitor.release()
            }
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
        case .nestedPill:
            return Self.nestedBatteryPillImage(values.battery)
        case .percentage, .available, .used, .remainingTime, .watts:
            return NSImage(systemSymbolName: MenuBarStatModel.symbolName(metric: metric, values: values), accessibilityDescription: nil)
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
        (NSApp.delegate as? AppDelegate)?.openSettings(selecting: .menuBar)
    }

    @objc private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func name(_ metric: MenuBarMetric) -> String { MenuBarStatModel.displayName(metric) }

    // MARK: - Template images for the drawing styles (tint to the menu bar automatically)

    private static func nestedBatteryPillImage(_ battery: MenuBarBattery?) -> NSImage {
        let label = MenuBarStatModel.batteryPillLabel(battery)
        let tone = MenuBarStatModel.batteryPillTone(battery)
        let charging = battery?.isCharging == true
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        let textColor: NSColor = tone == .warning ? NSColor(white: 0.08, alpha: 1) : .white
        let fillColor: NSColor = {
            switch tone {
            case .healthy, .charging: return .systemGreen
            case .warning: return .systemYellow
            case .critical: return .systemRed
            }
        }()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textSize = (label as NSString).size(withAttributes: attrs)
        let bodyWidth = ceil(max(26, textSize.width + (charging ? 15 : 8)))
        let totalWidth = bodyWidth + 3
        let image = NSImage(size: NSSize(width: totalWidth, height: 16), flipped: false) { _ in
            let bodyRect = NSRect(x: 0.5, y: 1.5, width: bodyWidth - 1, height: 13)
            let shell = NSBezierPath(roundedRect: bodyRect, xRadius: 3.5, yRadius: 3.5)
            fillColor.withAlphaComponent(0.92).setFill()
            shell.fill()
            fillColor.setStroke()
            shell.lineWidth = 1
            shell.stroke()

            let nubRect = NSRect(x: bodyWidth + 0.5, y: 5.5, width: 1.5, height: 5)
            fillColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: nubRect, xRadius: 0.75, yRadius: 0.75).fill()

            let boltWidth: CGFloat = charging ? 7 : 0
            let contentWidth = textSize.width + boltWidth + (charging ? 1 : 0)
            let textOrigin = NSPoint(
                x: ((bodyWidth - contentWidth) / 2).rounded(.toNearestOrAwayFromZero),
                y: ((16 - textSize.height) / 2).rounded(.toNearestOrAwayFromZero)
            )
            (label as NSString).draw(at: textOrigin, withAttributes: attrs)

            if charging,
               let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
                let tinted = NSImage(size: NSSize(width: 7, height: 10), flipped: false) { rect in
                    bolt.draw(in: rect)
                    textColor.setFill()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: textOrigin.x + textSize.width + 1, y: 3, width: 7, height: 10))
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func barImage(_ fraction: Double?) -> NSImage {
        let f = min(1, max(0, fraction ?? 0))
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            NSColor(white: 1, alpha: 0.3).setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 5, width: 14, height: 6), xRadius: 3, yRadius: 3).fill()
            NSColor(white: 1, alpha: 1).setFill()
            let snappedWidth = (max(2, 14 * f) * 2).rounded() / 2
            NSBezierPath(roundedRect: NSRect(x: 1, y: 5, width: snappedWidth, height: 6), xRadius: 3, yRadius: 3).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func pieImage(_ fraction: Double?) -> NSImage {
        let f = min(1, max(0, fraction ?? 0))
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            NSColor(white: 1, alpha: 0.25).setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12)).fill()
            NSColor(white: 1, alpha: 0.55).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 2.5, width: 11, height: 11))
            ring.lineWidth = 1
            ring.stroke()
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
