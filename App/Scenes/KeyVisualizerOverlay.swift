import AppKit
import SwiftUI

/// Phase 24d + KeyCastr-style upgrade: floating key visualizer overlay. Off by default, needs Input
/// Monitoring, and never logs or persists keystrokes — only holds the last few keycaps in memory and
/// clears itself after `lingerDuration`. Supports Glass Capsule, Svelte, and Dark Bezel styles plus
/// unlock-to-drag positioning.
@MainActor
final class KeyVisualizerController {
    private static let originXKey = "com.katikati.keyguard.visualizerOriginX"
    private static let originYKey = "com.katikati.keyguard.visualizerOriginY"

    private var panel: NSPanel?
    private let model = KeyVisualizerModel()
    private var moveObserver: NSObjectProtocol?

    /// Ordered oldest → newest, matching `KeyVisualizerBuffer.items`. Empty hides unless unlocked.
    func show(_ symbols: [String], config: KeyVisualizerConfig = KeyVisualizerConfig()) {
        model.symbols = symbols
        model.config = config
        if symbols.isEmpty && !config.isPositionUnlocked {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        applyInteractionMode(panel, unlocked: config.isPositionUnlocked)
        if !config.isPositionUnlocked { position(panel) }
        panel.orderFrontRegardless()
    }

    func setPositionUnlocked(_ unlocked: Bool, config: KeyVisualizerConfig) {
        model.config = config
        let panel = self.panel ?? makePanel()
        applyInteractionMode(panel, unlocked: unlocked)
        position(panel)
        if unlocked {
            panel.orderFrontRegardless()
        } else if model.symbols.isEmpty {
            panel.orderOut(nil)
        }
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.originXKey)
        UserDefaults.standard.removeObject(forKey: Self.originYKey)
        if let panel { position(panel) }
    }

    func hide() { panel?.orderOut(nil) }

    private func applyInteractionMode(_ panel: NSPanel, unlocked: Bool) {
        panel.ignoresMouseEvents = !unlocked
        panel.isMovableByWindowBackground = unlocked
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: KeyVisualizerView(model: model))
        host.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        panel.contentView = host
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveOrigin() }
        }
        self.panel = panel
        return panel
    }

    private func saveOrigin() {
        guard model.config.isPositionUnlocked, let panel else { return }
        UserDefaults.standard.set(Double(panel.frame.origin.x), forKey: Self.originXKey)
        UserDefaults.standard.set(Double(panel.frame.origin.y), forKey: Self.originYKey)
    }

    /// Uses saved drag origin when available; otherwise bottom-center of the screen under the pointer.
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        if UserDefaults.standard.object(forKey: Self.originXKey) != nil,
           UserDefaults.standard.object(forKey: Self.originYKey) != nil {
            let x = UserDefaults.standard.double(forKey: Self.originXKey)
            let y = UserDefaults.standard.double(forKey: Self.originYKey)
            let pt = NSPoint(x: x, y: y)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: pt, size: size)) }) {
                panel.setFrameOrigin(pt)
                return
            }
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                     y: screen.frame.minY + 120))
    }
}

@MainActor
private final class KeyVisualizerModel: ObservableObject {
    @Published var symbols: [String] = []
    @Published var config = KeyVisualizerConfig()
}

private struct KeyVisualizerView: View {
    @ObservedObject var model: KeyVisualizerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.symbols.isEmpty && model.config.isPositionUnlocked {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Drag Key Visualizer")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5))
            } else {
                keycapsRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78), value: model.symbols)
    }

    @ViewBuilder
    private var keycapsRow: some View {
        let fontSize = CGFloat(model.config.fontSize)
        switch model.config.style {
        case .glassCapsule:
            HStack(spacing: 6) {
                ForEach(Array(model.symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().strokeBorder(.quaternary))
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                }
            }
        case .svelte:
            HStack(spacing: 4) {
                ForEach(Array(model.symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.system(size: max(11, fontSize - 2), weight: .medium, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.thinMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.quaternary))
                }
            }
        case .darkBezel:
            HStack(spacing: 6) {
                ForEach(Array(model.symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.84)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.18)))
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                }
            }
        }
    }
}
