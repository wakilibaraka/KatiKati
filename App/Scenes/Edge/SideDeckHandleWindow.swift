import AppKit
import SwiftUI

/// SD-1 (render 1): the resting handle — a 4 × 44 pt capsule on the active edge, below the menu bar and above
/// the Dock, that opens the deck on hover.
///
/// A hidden floating panel receives no mouse events, and the plan forbids a global pointer monitor while
/// retiring the old 7 Hz `NSEvent.mouseLocation` poll. So the handle is its own always-present borderless
/// window with a tracking area: 4 pt of ink, padded to a 14 pt hit target (≤6 pt on either side), nothing
/// else on screen. Recorded as the choice the plan leaves open.
@MainActor
final class SideDeckHandleWindow {
    private var panel: NSPanel?
    private var host: NSView?
    private var dwellWork: DispatchWorkItem?
    private let onOpen: () -> Void

    static let inkWidth: CGFloat = 4
    static let inkHeight: CGFloat = 44
    static let hitPadding: CGFloat = 5

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
    }

    /// Places the handle on `screen`'s active edge, vertically centred between the menu bar and the Dock.
    func show(on screen: NSScreen, side: SideDeckConfig.Side) {
        let visible = screen.visibleFrame
        let width = Self.inkWidth + 2 * Self.hitPadding
        let height = Self.inkHeight + 2 * Self.hitPadding
        let x = side == .left ? visible.minX : visible.maxX - width
        let frame = NSRect(x: x, y: visible.midY - height / 2, width: width, height: height)

        let panel = panel ?? makePanel(frame: frame)
        panel.setFrame(frame, display: false)
        self.panel = panel

        let content = HandleTrackingView(frame: NSRect(origin: .zero, size: frame.size))
        content.onEnter = { [weak self] in self?.scheduleOpen() }
        content.onExit = { [weak self] in self?.cancelOpen() }
        let hosting = NSHostingView(rootView: SideDeckHandleCapsule())
        hosting.frame = content.bounds
        hosting.autoresizingMask = [.width, .height]
        content.addSubview(hosting)
        panel.contentView = content
        host = content
        panel.orderFrontRegardless()
    }

    func hide() {
        cancelOpen()
        panel?.orderOut(nil)
        panel = nil
        host = nil
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = PanelCollectionBehavior.standard
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// 180 ms by default: enough that crossing the edge on the way somewhere else never opens the deck.
    private func scheduleOpen() {
        cancelOpen()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onOpen()
            }
        }
        dwellWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SideDeckConfig.migrating(from: .standard).dwell,
                                      execute: work)
    }

    private func cancelOpen() {
        dwellWork?.cancel()
        dwellWork = nil
    }
}

private struct SideDeckHandleCapsule: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.accentColor.opacity(0.25))
            .frame(width: SideDeckHandleWindow.inkWidth, height: SideDeckHandleWindow.inkHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text("Open"))
    }
}

/// The hit target: a plain view whose tracking area covers the padded frame, so a 4 pt capsule is grabbable
/// without widening the ink.
private final class HandleTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
