import AppKit
import Combine
import SwiftUI

/// Pass 2 — the menu-bar readout is multi-metric (Stats-style): one status item per enabled
/// metric, each with its own display style, and a click menu with every reading plus the usual
/// shortcuts. Off by default: the items and the 1 s sampler exist only while at least one metric
/// is on, so a user who never enables it pays nothing (the Phase 20c discipline, kept).
@MainActor
final class MenuBarSystemItem: NSObject, NSMenuDelegate {
    /// The master switch; same key the old single CPU/MEM readout used.
    static let enabledKey = MenuBarStatModel.masterEnabledKey

    private struct RenderKey: Equatable {
        let style: MenuBarMetricStyle
        let pillLabel: String
        let tone: MenuBarBatteryPillTone?
        let charging: Bool
        let bucket: Int?
        let symbol: String?
    }

    private let monitor = SystemMonitorController.shared
    private var items: [MenuBarMetric: NSStatusItem] = [:]
    private var imageCache: [MenuBarMetric: (key: RenderKey, image: NSImage?)] = [:]
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
            imageCache[metric] = nil
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
        let key: RenderKey
        switch style {
        case .nestedPill:
            key = RenderKey(
                style: style,
                pillLabel: MenuBarStatModel.batteryPillLabel(values.battery),
                tone: MenuBarStatModel.batteryPillTone(values.battery),
                charging: values.battery?.isCharging == true,
                bucket: nil,
                symbol: nil
            )
        case .barGraph, .pieChart:
            let bucket = Int(((MenuBarStatModel.imageFraction(metric: metric, values: values) ?? 0) * 100).rounded())
            key = RenderKey(style: style, pillLabel: "", tone: nil, charging: false, bucket: bucket, symbol: nil)
        case .iconOnly, .percentage, .available, .used, .remainingTime, .watts:
            let symbol = MenuBarStatModel.symbolName(metric: metric, values: values)
            key = RenderKey(style: style, pillLabel: "", tone: nil, charging: false, bucket: nil, symbol: symbol)
        }
        if let cached = imageCache[metric], cached.key == key {
            return cached.image
        }
        let rendered: NSImage?
        switch style {
        case .barGraph:
            rendered = Self.barImage(MenuBarStatModel.imageFraction(metric: metric, values: values))
        case .pieChart:
            rendered = Self.pieImage(MenuBarStatModel.imageFraction(metric: metric, values: values))
        case .iconOnly, .percentage, .available, .used, .remainingTime, .watts:
            rendered = key.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        case .nestedPill:
            rendered = Self.nestedBatteryPillImage(values.battery)
        }
        imageCache[metric] = (key, rendered)
        return rendered
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
        AppDelegate.shared?.openSettings(selecting: .menuBar)
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
        let boltImage: NSImage? = charging
            ? NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: 8.5, weight: .bold)
                        .applying(.init(hierarchicalColor: textColor))
                )
            : nil
        let boltWidth = boltImage?.size.width ?? 0
        let boltGap: CGFloat = boltWidth > 0 ? 1.5 : 0
        let contentWidth = textSize.width + boltGap + boltWidth
        let bodyWidth = ceil(max(26, contentWidth + 8))
        let totalWidth = bodyWidth + 2.5
        let image = NSImage(size: NSSize(width: totalWidth, height: 16), flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            let bodyRect = NSRect(x: 0.5, y: 1.5, width: bodyWidth - 1, height: 13)
            let shell = NSBezierPath(roundedRect: bodyRect, xRadius: 3.5, yRadius: 3.5)
            fillColor.withAlphaComponent(0.92).setFill()
            shell.fill()
            fillColor.setStroke()
            shell.lineWidth = 1
            shell.stroke()

            let nubRect = NSRect(x: bodyWidth, y: 5.5, width: 1.5, height: 5)
            fillColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: nubRect, xRadius: 0.75, yRadius: 0.75).fill()

            let textOrigin = NSPoint(
                x: ((bodyWidth - contentWidth) / 2).rounded(.toNearestOrAwayFromZero),
                y: (bodyRect.midY + font.descender - font.capHeight / 2).rounded(.toNearestOrAwayFromZero)
            )
            (label as NSString).draw(at: textOrigin, withAttributes: attrs)

            if let boltImage {
                let boltSize = boltImage.size
                let boltRect = NSRect(
                    x: textOrigin.x + textSize.width + boltGap,
                    y: bodyRect.midY - boltSize.height / 2,
                    width: boltSize.width,
                    height: boltSize.height
                )
                boltImage.draw(in: boltRect)
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

// MARK: - MB-2: Status Trio Ring Menu Bar Renderer

@MainActor
enum StatusTrioIconRenderer {
    private static var cache: [StatusTrioRenderKey: NSImage] = [:]

    /// Stacked day number over the month abbreviation, like a desk calendar. Template ink so it
    /// inverts with the menu bar; the month name comes from the user's locale.
    static func dateImage(hasUpdateDot: Bool, now: Date = Date()) -> NSImage {
        let day = Calendar.current.component(.day, from: now)
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        let month = formatter.string(from: now).uppercased().replacingOccurrences(of: ".", with: "")
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            let ink = NSColor.black
            let monthText = month as NSString
            let monthAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7, weight: .semibold),
                .foregroundColor: ink,
                .kern: 0.2,
            ]
            let monthSize = monthText.size(withAttributes: monthAttrs)
            monthText.draw(at: NSPoint(x: ((20 - monthSize.width) / 2).rounded(), y: 11.5), withAttributes: monthAttrs)

            let dayText = "\(day)" as NSString
            let dayAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .bold),
                .foregroundColor: ink,
            ]
            let daySize = dayText.size(withAttributes: dayAttrs)
            dayText.draw(at: NSPoint(x: ((20 - daySize.width) / 2).rounded(), y: 0.5), withAttributes: dayAttrs)

            if hasUpdateDot {
                let dot = NSRect(x: 15.5, y: 15.5, width: 4, height: 4)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                ink.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "KatiKati"
        return image
    }

    static func image(for key: StatusTrioRenderKey) -> NSImage {
        if let cached = cache[key] { return cached }
        if cache.count >= 12 { cache.removeAll(keepingCapacity: true) }

        // 20 pt inside the menu bar's fixed 22 pt working area: a 16 pt circular glyph matches
        // system weight, and 18 was reading smaller than Wi-Fi/battery next to it.
        let iconSide: CGFloat = 20
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        let primaryInk: NSColor = key.semanticColor
            ? (key.isDarkMenuBar ? NSColor.white.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.88))
            : .black
        let readoutAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: primaryInk]
        let readoutSize = key.readoutText.map { ($0 as NSString).size(withAttributes: readoutAttrs) } ?? .zero
        let totalWidth = iconSide + (key.readoutText == nil ? 0 : 3 + ceil(readoutSize.width))

        let rendered = NSImage(size: NSSize(width: totalWidth, height: iconSide), flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            let center = NSPoint(x: iconSide / 2, y: iconSide / 2)
            let radius: CGFloat = 8.0
            let lineWidth = CGFloat(key.stroke.lineWidth)

            drawBatteryArc(key: key, center: center, radius: radius, lineWidth: lineWidth, ink: primaryInk)
            drawCenterLink(key.link, center: center, stroke: lineWidth, ink: primaryInk)
            drawVolumeDots(key: key, center: center, radius: radius, dotSize: lineWidth + 1.0, ink: primaryInk)

            if let text = key.readoutText {
                let origin = NSPoint(
                    x: iconSide + 3,
                    y: (iconSide / 2 + font.descender - font.capHeight / 2).rounded(.toNearestOrAwayFromZero)
                )
                (text as NSString).draw(at: origin, withAttributes: readoutAttrs)
            }
            if key.hasUpdateDot {
                drawUpdateDot(iconSide: iconSide, semanticColor: key.semanticColor, ink: primaryInk)
            }
            return true
        }
        rendered.isTemplate = !key.semanticColor
        rendered.accessibilityDescription = accessibilityLabel(for: key)
        cache[key] = rendered
        return rendered
    }

    private static func drawBatteryArc(
        key: StatusTrioRenderKey, center: NSPoint, radius: CGFloat, lineWidth: CGFloat, ink: NSColor
    ) {
        let track = NSBezierPath()
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        track.appendArc(withCenter: center, radius: radius, startAngle: 150, endAngle: 30, clockwise: true)
        ink.withAlphaComponent(0.32).setStroke()
        track.stroke()

        let fraction = key.batteryBucket.map { Double($0) / 20.0 } ?? 1.0
        guard fraction > 0 else { return }
        let endAngle = 150 - 120 * fraction
        let fill = NSBezierPath()
        fill.lineWidth = lineWidth
        fill.lineCapStyle = .round
        fill.appendArc(withCenter: center, radius: radius, startAngle: 150, endAngle: endAngle, clockwise: true)
        batteryColor(key: key, ink: ink).setStroke()
        fill.stroke()

        if key.isCharging {
            let rad = endAngle * .pi / 180
            let tip = NSPoint(x: center.x + cos(rad) * radius, y: center.y + sin(rad) * radius)
            let dot = NSRect(x: tip.x - 1.3, y: tip.y - 1.3, width: 2.6, height: 2.6)
            (key.semanticColor ? NSColor.systemGreen : ink).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    private static func drawCenterLink(_ link: NetworkLinkKind, center: NSPoint, stroke: CGFloat, ink: NSColor) {
        switch link {
        case .wifi(let steps):
            let dotR: CGFloat = 0.85
            ink.withAlphaComponent(steps > 0 ? 1 : 0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - dotR, y: center.y - 2.3 - dotR, width: dotR * 2, height: dotR * 2)).fill()
            for idx in 1...3 {
                let arc = NSBezierPath()
                arc.lineWidth = max(0.95, stroke * 0.72)
                arc.lineCapStyle = .round
                arc.appendArc(withCenter: NSPoint(x: center.x, y: center.y - 2.3),
                              radius: CGFloat(idx) * 1.8, startAngle: 48, endAngle: 132, clockwise: false)
                ink.withAlphaComponent(idx <= steps ? 1 : 0.25).setStroke()
                arc.stroke()
            }
        case .ethernet:
            let bar = NSBezierPath(roundedRect: NSRect(x: center.x - 3.2, y: center.y - 1.5, width: 6.4, height: 3.0),
                                   xRadius: 0.9, yRadius: 0.9)
            bar.lineWidth = max(0.95, stroke * 0.7)
            ink.setStroke()
            bar.stroke()
        case .hotspot:
            for dx in [-1.6, 1.6] as [CGFloat] {
                let ring = NSBezierPath(ovalIn: NSRect(x: center.x + dx - 1.9, y: center.y - 1.9, width: 3.8, height: 3.8))
                ring.lineWidth = max(0.95, stroke * 0.7)
                ink.setStroke()
                ring.stroke()
            }
        case .bluetoothAudio:
            let glyph = NSImage(systemSymbolName: "airpodspro", accessibilityDescription: nil)
            glyph?.isTemplate = true
            glyph?.draw(in: NSRect(x: center.x - 3.8, y: center.y - 3.2, width: 7.6, height: 6.4))
        case .offline:
            ink.withAlphaComponent(0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 1.4, y: center.y - 1.4, width: 2.8, height: 2.8)).fill()
            let slash = NSBezierPath()
            slash.lineWidth = max(1.0, stroke * 0.72)
            slash.lineCapStyle = .round
            slash.move(to: NSPoint(x: center.x - 3.1, y: center.y - 2.6))
            slash.line(to: NSPoint(x: center.x + 3.1, y: center.y + 2.6))
            ink.withAlphaComponent(0.85).setStroke()
            slash.stroke()
        }
    }

    private static func drawVolumeDots(
        key: StatusTrioRenderKey, center: NSPoint, radius: CGFloat, dotSize: CGFloat, ink: NSColor
    ) {
        let angles: [CGFloat] = [236, 270, 304]
        for (idx, deg) in angles.enumerated() {
            let rad = deg * .pi / 180
            let pt = NSPoint(x: center.x + cos(rad) * radius, y: center.y + sin(rad) * radius)
            let active = !key.isMuted && idx < key.volumeDots
            ink.withAlphaComponent(active ? 1.0 : 0.32).setFill()
            NSBezierPath(ovalIn: NSRect(x: pt.x - dotSize / 2, y: pt.y - dotSize / 2, width: dotSize, height: dotSize)).fill()
        }
        if key.isMuted {
            let slash = NSBezierPath()
            slash.lineWidth = max(1.0, CGFloat(key.stroke.lineWidth) * 0.72)
            slash.lineCapStyle = .round
            slash.move(to: NSPoint(x: center.x - 4.2, y: center.y - radius - 1.2))
            slash.line(to: NSPoint(x: center.x + 4.2, y: center.y - radius + 1.2))
            ink.withAlphaComponent(0.9).setStroke()
            slash.stroke()
        }
    }

    private static func drawUpdateDot(iconSide: CGFloat, semanticColor: Bool, ink: NSColor) {
        let diameter: CGFloat = 4.0
        let dot = NSRect(x: iconSide - diameter, y: iconSide - diameter, width: diameter, height: diameter)
        if !semanticColor {
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.1, dy: -1.1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            ink.setFill()
        } else {
            NSColor.systemRed.setFill()
        }
        NSBezierPath(ovalIn: dot).fill()
    }

    private static func batteryColor(key: StatusTrioRenderKey, ink: NSColor) -> NSColor {
        guard key.semanticColor else { return ink }
        if key.isCharging { return .systemGreen }
        if key.isLowBattery { return .systemRed }
        return ink
    }

    private static func accessibilityLabel(for key: StatusTrioRenderKey) -> String {
        key.hasUpdateDot ? String(localized: "KatiKati — update available") : "KatiKati"
    }
}

/// Event-driven coordinator driving KatiKati's primary Status Trio menu-bar icon (0% idle CPU).
@MainActor
final class MenuBarStatusCoordinator {
    private let statusService = SystemStatusService()
    private var statusSink: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    var onIconChanged: () -> Void = {}

    var isOutputMuted: Bool { statusService.status.volume.isMuted }

    func start() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncObservation()
                self?.onIconChanged()
            }
        }
        syncObservation()
        onIconChanged()
    }

    @discardableResult
    func toggleOutputMute() -> Bool {
        if !statusService.isRunning { statusService.acquire() }
        return statusService.toggleMute()
    }

    func renderStatusBarIcon(for button: NSStatusBarButton?, hasUpdateDot: Bool) -> NSImage? {
        let mode = MenuBarIconMode.current()
        if mode == .date { return StatusTrioIconRenderer.dateImage(hasUpdateDot: hasUpdateDot) }
        guard mode == .statusTrio else { return nil }
        let appearance = button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let defaults = UserDefaults.standard
        let showBT = (defaults.object(forKey: MenuBarHubPrefs.bluetoothInRingKey) as? Bool) ?? true
        let key = StatusTrioRenderKey(
            status: statusService.status,
            stroke: .current(defaults),
            semanticColor: defaults.bool(forKey: MenuBarHubPrefs.semanticAlertsKey),
            showCompactReadout: defaults.bool(forKey: MenuBarHubPrefs.compactReadoutKey),
            showBluetoothAudio: showBT,
            isDarkMenuBar: isDark,
            hasUpdateDot: hasUpdateDot
        )
        return StatusTrioIconRenderer.image(for: key)
    }

    private func syncObservation() {
        let wantsRing = MenuBarIconMode.current() == .statusTrio
        if wantsRing, statusSink == nil {
            statusService.acquire()
            statusSink = statusService.$status.sink { [weak self] _ in self?.onIconChanged() }
        } else if !wantsRing, statusSink != nil {
            statusSink = nil
            statusService.release()
        }
    }
}

// MARK: - MB-6: Left-Click Creative Hub Glass Flyout Controller

private final class HubFlyoutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class MenuBarHubPanelController {
    private var panel: HubFlyoutPanel?
    private var outsideMonitor: Any?
    private var anchorScreenRect: CGRect = .zero

    var onWillShow: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var themeStyle: () -> DockThemeStyle = { .auto }
    var themeTuning: () -> ThemeTuning = { .identity }
    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo button: NSStatusBarButton) { isShown ? hide() : show(relativeTo: button) }

    func show(relativeTo button: NSStatusBarButton) {
        onWillShow()
        guard let window = button.window else { return }
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        anchorScreenRect = buttonRect

        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = (screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)).insetBy(dx: 8, dy: 8)
        // The status item hosts whichever surface the owner chose: the Creative Hub, or the Control
        // Centre when they moved it to the menu bar (the two stay mutually exclusive).
        let surfaceMode = ControlCenterSurfaceMode.parse(UserDefaults.standard.string(forKey: ControlCenterSurfaceMode.storageKey))
        let size = surfaceMode == .menuBar
            ? CGSize(width: ControlCenterSize.parse(UserDefaults.standard.string(forKey: ControlCenterSize.storageKey)).width, height: 520)
            : CGSize(width: MenuBarCreativeHubView.panelWidth,
                     height: MenuBarCreativeHubView.panelHeight + HubCaretPlan.height)
        let x = min(max(buttonRect.midX - size.width / 2, visible.minX), visible.maxX - size.width)
        // No gap now: the pointer strip takes the old 6 pt gap and its tip touches the icon's edge.
        let y = max(visible.minY, buttonRect.minY + 1 - size.height)
        let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        let caretX = operatorX(buttonRect: buttonRect, frame: frame)

        let p = panel ?? makePanel()
        panel = p
        let root: AnyView = surfaceMode == .menuBar
            ? AnyView(ControlCenterView(
                engine: .shared,
                order: QuickToggleID.defaultOrder,
                widgetTiles: TileKind.controlCenterDefault,
                style: ControlCenterStyle.parse(UserDefaults.standard.string(forKey: ControlCenterStyle.storageKey)),
                onSettings: { [weak self] in self?.hide(); self?.onOpenSettings() })
                .frame(width: size.width, height: size.height)
                .environment(\.dockThemeStyle, themeStyle())
                .environment(\.themeTuning, themeTuning()))
            : AnyView(MenuBarCreativeHubView(
                onDismiss: { [weak self] in self?.hide() },
                onOpenSettings: { [weak self] in self?.hide(); self?.onOpenSettings() },
                caretX: caretX
            )
            .environment(\.dockThemeStyle, themeStyle())
            .environment(\.themeTuning, themeTuning()))

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        p.contentView = hosting
        p.setFrame(frame, display: true)
        p.makeKeyAndOrderFront(nil)
        installOutsideMonitor()
    }

    /// The icon's centre expressed inside the panel, so a clamped panel still points at the icon.
    private func operatorX(buttonRect: CGRect, frame: CGRect) -> CGFloat {
        buttonRect.midX - frame.minX
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
    }

    private func makePanel() -> HubFlyoutPanel {
        let p = HubFlyoutPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isFloatingPanel = true
        p.isMovable = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.onEscape = { [weak self] in self?.hide() }
        return p
    }

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                let pt = NSEvent.mouseLocation
                if !panel.frame.contains(pt) && !self.anchorScreenRect.contains(pt) { self.hide() }
            }
        }
    }
}
