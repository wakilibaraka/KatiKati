import AppKit
import SwiftUI

/// SN-4: a read-only card about the window in front of the user — which app, which frame, which
/// display, how much memory and CPU it is using right now. It reads through Accessibility and the
/// same `ri_phys_footprint` reader the RAM tab uses, so the numbers match Activity Monitor instead of
/// reporting resident pages. Nothing is written back: this is a lens, not a tool.
@MainActor
final class WindowInspectorController {
    static let shared = WindowInspectorController()

    fileprivate struct ScreenInfo: Sendable {
        let frame: CGRect
        let name: String
        let scale: CGFloat
    }

    fileprivate struct ScreenGeometrySnapshot: Sendable {
        let primaryMaxY: CGFloat
        let screens: [ScreenInfo]
    }

    private var panel: NSPanel?
    private var hosting: NSHostingView<WindowInspectorView>?
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var cachedScreens: ScreenGeometrySnapshot?
    private let readQueue = DispatchQueue(label: "com.katikati.windowInspector", qos: .utility)
    private var readToken: UInt64 = 0
    private var lastCPU: (pid: Int32, wall: TimeInterval, ticks: UInt64)?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = ensurePanel()
        refreshScreenCache()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshScreenCache() }
            }
        }
        refresh()
        position(panel)
        panel.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.1
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        cachedScreens = nil
        readToken &+= 1
        lastCPU = nil
        panel?.orderOut(nil)
    }

    private func refreshScreenCache() {
        let screens = NSScreen.screens
        let primaryMaxY = screens.first?.frame.maxY ?? 0
        cachedScreens = ScreenGeometrySnapshot(
            primaryMaxY: primaryMaxY,
            screens: screens.map { ScreenInfo(frame: $0.frame, name: $0.localizedName, scale: $0.backingScaleFactor) }
        )
    }

    private func refresh() {
        guard hosting != nil else { return }
        guard AXIsProcessTrusted() else {
            hosting?.rootView = WindowInspectorView(snapshot: nil, needsAccessibility: true)
            if let hosting { panel?.setContentSize(hosting.fittingSize) }
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            lastCPU = nil
            hosting?.rootView = WindowInspectorView(snapshot: nil, needsAccessibility: false)
            if let hosting { panel?.setContentSize(hosting.fittingSize) }
            return
        }
        if cachedScreens == nil { refreshScreenCache() }
        let screens = cachedScreens ?? ScreenGeometrySnapshot(primaryMaxY: 0, screens: [])
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "—"
        let bundleID = app.bundleIdentifier ?? "—"
        let previousCPU = lastCPU
        readToken &+= 1
        let token = readToken

        readQueue.async { [weak self] in
            let result = InspectorSnapshot.readOffMain(
                pid: pid,
                appName: appName,
                bundleID: bundleID,
                screens: screens,
                previousCPU: previousCPU
            )
            DispatchQueue.main.async {
                guard let self, self.readToken == token, self.isVisible, let hosting = self.hosting else { return }
                self.lastCPU = result.cpuSample
                hosting.rootView = WindowInspectorView(snapshot: result.snapshot, needsAccessibility: false)
                self.panel?.setContentSize(hosting.fittingSize)
            }
        }
    }

    private func position(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        var origin = CGPoint(x: pointer.x + 16, y: pointer.y - size.height - 16)
        if origin.x + size.width > visible.maxX - 8 { origin.x = pointer.x - size.width - 16 }
        if origin.y < visible.minY + 8 { origin.y = pointer.y + 16 }
        origin.x = min(max(origin.x, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8))
        origin.y = min(max(origin.y, visible.minY + 8), max(visible.minY + 8, visible.maxY - size.height - 8))
        panel.setFrameOrigin(origin)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: WindowInspectorView(snapshot: nil, needsAccessibility: false))
        hosting.setFrameSize(hosting.fittingSize)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    struct InspectorSnapshot: Equatable, Sendable {
        var title = "—"
        var app = "—"
        var bundle = "—"
        var pid: Int32 = 0
        var frame: CGRect = .zero
        var display = "—"
        var scale: CGFloat = 1
        var memory: UInt64 = 0
        var cpu: Double = 0

        fileprivate nonisolated static func readOffMain(
            pid: Int32,
            appName: String,
            bundleID: String,
            screens: ScreenGeometrySnapshot,
            previousCPU: (pid: Int32, wall: TimeInterval, ticks: UInt64)?
        ) -> (snapshot: InspectorSnapshot?, cpuSample: (pid: Int32, wall: TimeInterval, ticks: UInt64)?) {
            let appElement = AXMessagingPolicy.applyTimeout(AXUIElementCreateApplication(pid))
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
                  let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return (nil, nil) }
            let window = AXMessagingPolicy.applyTimeout(ref as! AXUIElement)

            var snapshot = InspectorSnapshot()
            snapshot.app = appName
            snapshot.bundle = bundleID
            snapshot.pid = pid
            snapshot.title = string(window, kAXTitleAttribute) ?? "—"
            let quartzFrame = frame(of: window) ?? .zero
            let cocoaFrame = WindowInspectorMath.cocoaFrame(fromQuartz: quartzFrame, primaryMaxY: screens.primaryMaxY)
            snapshot.frame = cocoaFrame
            if let screen = screens.screens.first(where: { $0.frame.contains(CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)) }) {
                snapshot.display = screen.name
                snapshot.scale = screen.scale
            }

            var usage = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            var nextSample: (pid: Int32, wall: TimeInterval, ticks: UInt64)?
            if status == 0 {
                snapshot.memory = usage.ri_phys_footprint
                let wall = ProcessInfo.processInfo.systemUptime
                let ticks = usage.ri_user_time + usage.ri_system_time
                var timebase = mach_timebase_info_data_t()
                mach_timebase_info(&timebase)
                let current = (pid: pid, wall: wall, ticks: ticks)
                snapshot.cpu = WindowInspectorMath.cpuPercent(
                    previous: previousCPU,
                    current: current,
                    timebaseNumer: timebase.numer,
                    timebaseDenom: timebase.denom
                )
                nextSample = current
            }
            return (snapshot, nextSample)
        }

        private nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
            return (ref as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private nonisolated static func frame(of window: AXUIElement) -> CGRect? {
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            var point = CGPoint.zero
            var size = CGSize.zero
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
                  let positionRef, CFGetTypeID(positionRef) == AXValueGetTypeID(),
                  AXValueGetValue(positionRef as! AXValue, .cgPoint, &point),
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID(),
                  AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
            return CGRect(origin: point, size: size)
        }
    }
}

struct WindowInspectorView: View {
    var snapshot: WindowInspectorController.InspectorSnapshot?
    var needsAccessibility: Bool = false
    @Environment(\.colorScheme) private var scheme

    private var ink: Color { scheme == .dark ? .white : .black }
    private var fill: Color { ink.opacity(scheme == .dark ? 0.10 : 0.05) }
    private var stroke: Color { ink.opacity(scheme == .dark ? 0.16 : 0.10) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = snapshot {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: s.title).font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ink).lineLimit(2)
                    Text(verbatim: s.app).font(.system(size: 10.5)).foregroundStyle(ink.opacity(0.6)).lineLimit(1)
                }
                Divider().opacity(0.3)
                row(Text("App"), s.bundle)
                row(Text("PID"), String(s.pid))
                row(Text("Frame"), String(format: "%.0f, %.0f · %.0f × %.0f", s.frame.minX, s.frame.minY, s.frame.width, s.frame.height))
                row(Text("Display"), "\(s.display) · \(String(format: "%.0f", s.scale))×")
                row(Text("Memory"), AppMemorySampler.formatBytes(s.memory))
                row(Text("CPU"), String(format: "%.0f%%", s.cpu))
            } else {
                Text("Window Inspector").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                if needsAccessibility {
                    Text("Accessibility").font(.system(size: 11)).foregroundStyle(ink.opacity(0.65))
                } else {
                    Text(verbatim: "—").font(.system(size: 11)).foregroundStyle(ink.opacity(0.55))
                }
            }
        }
        .padding(12)
        .frame(width: 264, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(stroke, lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
    }

    private func row(_ label: Text, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            label.font(.system(size: 10.5, weight: .medium)).foregroundStyle(ink.opacity(0.55))
                .frame(width: 58, alignment: .leading)
            Text(verbatim: value).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ink)
                .lineLimit(1).truncationMode(.middle)
        }
    }
}
