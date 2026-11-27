import AppKit
import SwiftUI

/// SN-4: a read-only card about the window in front of the user — which app, which frame, which
/// display, how much memory and CPU it is using right now. It reads through Accessibility and the
/// same `ri_phys_footprint` reader the RAM tab uses, so the numbers match Activity Monitor instead of
/// reporting resident pages. Nothing is written back: this is a lens, not a tool.
@MainActor
final class WindowInspectorController {
    static let shared = WindowInspectorController()

    private var panel: NSPanel?
    private var hosting: NSHostingView<WindowInspectorView>?
    private var timer: Timer?
    private var keyMonitor: Any?
    private var lastCPU: (wall: TimeInterval, ticks: UInt64)?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = ensurePanel()
        refresh()
        position(panel)
        panel.orderFrontRegardless()
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }   // esc
                self?.hide()
                return nil
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        lastCPU = nil
        panel?.orderOut(nil)
    }

    private func refresh() {
        guard let hosting else { return }
        hosting.rootView = WindowInspectorView(snapshot: InspectorSnapshot.read(cpuSample: &lastCPU))
        panel?.setContentSize(hosting.fittingSize)
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
        let hosting = NSHostingView(rootView: WindowInspectorView(snapshot: nil))
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
}

struct InspectorSnapshot: Equatable {
    var title = "—"
    var app = "—"
    var bundle = "—"
    var pid: Int32 = 0
    var frame: CGRect = .zero
    var display = "—"
    var scale: CGFloat = 1
    var memory: UInt64 = 0
    var cpu: Double = 0

    /// `cpuSample` carries the previous `ri_user_time + ri_system_time` reading so the card can show a
    /// percentage instead of a total. Same-user processes only, like the RAM tab.
    static func read(cpuSample: inout (wall: TimeInterval, ticks: UInt64)?) -> InspectorSnapshot? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let pid = app.processIdentifier
        let appElement = AXMessagingPolicy.applyTimeout(AXUIElementCreateApplication(pid))
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let window = AXMessagingPolicy.applyTimeout(ref as! AXUIElement)

        var snapshot = InspectorSnapshot()
        snapshot.app = app.localizedName ?? "—"
        snapshot.bundle = app.bundleIdentifier ?? "—"
        snapshot.pid = pid
        snapshot.title = string(window, kAXTitleAttribute) ?? "—"
        snapshot.frame = frame(of: window) ?? .zero
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: snapshot.frame.midX, y: snapshot.frame.midY)) }),
           let primary = NSScreen.screens.first {
            snapshot.display = screen.localizedName
            snapshot.scale = screen.backingScaleFactor
            snapshot.frame = CGRect(x: snapshot.frame.minX,
                                    y: primary.frame.maxY - snapshot.frame.maxY,
                                    width: snapshot.frame.width,
                                    height: snapshot.frame.height)
        }
        snapshot.memory = AppMemorySampler.physicalFootprintBytes(for: pid)

        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        if status == 0 {
            let wall = ProcessInfo.processInfo.systemUptime
            let ticks = usage.ri_user_time + usage.ri_system_time
            if let last = cpuSample, wall > last.wall, ticks >= last.ticks {
                // rusage times are nanoseconds on macOS, so ticks over nanoseconds of wall is the share.
                snapshot.cpu = min(100, Double(ticks - last.ticks) / ((wall - last.wall) * 1_000_000_000) * 100)
            }
            cpuSample = (wall, ticks)
        }
        return snapshot
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return (ref as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
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

struct WindowInspectorView: View {
    var snapshot: InspectorSnapshot?
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
                Text(verbatim: "—").font(.system(size: 11)).foregroundStyle(ink.opacity(0.55))
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
