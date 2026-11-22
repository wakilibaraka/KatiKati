import AppKit
import SwiftUI

/// Quick Settings / Control Center button displaying a central Wi-Fi icon
/// surrounded by a circular Volume ring + 12 radial volume dots indicating macOS system volume (0-100%).
/// Supports scroll-wheel volume adjustment (consuming scroll events locally) and Liquid Glass capsule mode.
public struct WiFiVolumeFABView: View {
    @StateObject private var status = SystemStatusService()
    @State private var isHovered = false
    var capsuleMode: Bool = false
    var dockScale: CGFloat = 1.0
    var onTap: (() -> Void)?

    public init(capsuleMode: Bool = false, dockScale: CGFloat = 1.0, onTap: (() -> Void)? = nil) {
        self.capsuleMode = capsuleMode
        self.dockScale = dockScale
        self.onTap = onTap
    }

    public var body: some View {
        let volume = status.status.volume
        let wifi = status.status.wifi
        let volumeLevel = volume.isMuted ? 0.0 : Double(volume.level)
        let activeDots = volume.isMuted ? 0 : Int(round(volumeLevel * 12.0))
        let visualScale = capsuleMode ? max(0.5, (54 * dockScale) / 40) : 1.0

        ZStack {
            // Subtle inner glass highlight + circular volume ring around the Wi-Fi glyph
            volumeArcRing(level: volumeLevel, isMuted: volume.isMuted)

            // Circular ring of 12 discrete volume dots
            volumeDotsRing(activeCount: activeDots, isMuted: volume.isMuted)

            // Central Wi-Fi symbol reflecting live signal/power state
            Image(systemName: wifi.symbolName, variableValue: wifi.isConnected ? wifi.symbolVariableValue : nil)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isHovered ? 1.0 : (wifi.isPoweredOn ? 0.92 : 0.6)))
        }
        .frame(width: 40, height: 40)
        .scaleEffect(visualScale)
        .modifier(CapsuleOrTileModifier(capsuleMode: capsuleMode, isHovered: isHovered))
        .contentShape(Rectangle())
        .overlay(
            CapsuleVolumeScrollCatcher { delta, precise in
                let step = Float(precise ? delta * 0.008 : delta * 0.04)
                let next = min(max(status.status.volume.level + step, 0), 1)
                status.setVolume(next)
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            status.acquire()
        }
        .onDisappear {
            status.release()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Control Center"))
        .accessibilityAddTraits(.isButton)
        .help(Text(verbatim: volume.isMuted ? "Control Center • Muted" : "Control Center • Volume: \(volume.percent)%"))
    }

    // MARK: - Circular Volume Ring + 12 Dots

    @ViewBuilder
    private func volumeArcRing(level: Double, isMuted: Bool) -> some View {
        ZStack {
            if capsuleMode {
                if #available(macOS 26.0, *) {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(isHovered ? 0.34 : 0.20), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                        .frame(width: 34, height: 34)
                } else {
                    Circle()
                        .strokeBorder(Color.white.opacity(isHovered ? 0.24 : 0.12), lineWidth: 0.75)
                        .frame(width: 34, height: 34)
                }
            }
            Circle()
                .stroke(Color.white.opacity(isMuted ? 0.07 : 0.14), lineWidth: 1.6)
                .frame(width: 28, height: 28)
            Circle()
                .trim(from: 0, to: min(max(level, 0), 1))
                .stroke(
                    isMuted ? Color.secondary.opacity(0.4) : Color.white.opacity(isHovered ? 0.95 : 0.78),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.28, dampingFraction: 0.8), value: level)
        }
    }

    private func volumeDotsRing(activeCount: Int, isMuted: Bool) -> some View {
        let radius: Double = 14.0
        return ZStack {
            ForEach(0..<12, id: \.self) { index in
                let angle = -90.0 + Double(index) * 30.0
                let rad = angle * .pi / 180.0
                let x = radius * cos(rad)
                let y = radius * sin(rad)
                let isActive = !isMuted && index < activeCount

                Circle()
                    .fill(isActive ? Color.white.opacity(0.96) : Color.white.opacity(isMuted ? 0.08 : 0.18))
                    .frame(width: 2.3, height: 2.3)
                    .offset(x: CGFloat(x), y: CGFloat(y))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
            }
        }
        .frame(width: 40, height: 40)
    }
}

private struct CapsuleOrTileModifier: ViewModifier {
    let capsuleMode: Bool
    let isHovered: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if capsuleMode {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content.dockTileChrome(isHovered: isHovered)
        }
    }
}

/// Consumes scroll-wheel events locally over the Control Center Wi-Fi + Volume ring without forwarding
/// them to the main dock strip scroll view (momentum phases are ignored so volume doesn't overshoot).
private struct CapsuleVolumeScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> CapsuleVolumeScrollView {
        let view = CapsuleVolumeScrollView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: CapsuleVolumeScrollView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private final class CapsuleVolumeScrollView: NSView {
    var onScroll: ((CGFloat, Bool) -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil, NSApp.currentEvent?.type == .scrollWheel else { return nil }
        return self
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.05 else { return }
        onScroll?(delta, event.hasPreciseScrollingDeltas)
    }
}
