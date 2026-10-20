import AppKit
import SwiftUI

// 50e (owner 2026-10-21): a new song announces itself as a small pill that drops out from under the
// notch, like the USB eject pill, instead of opening the whole notch. It is its own panel so a click
// can dismiss it, and it reads the live feed so artwork that arrives late still shows.

@MainActor
final class NotchTrackPillController {
    private var panel: NSPanel?
    private var model: NotchTrackPillModel?
    private var dismissWork: DispatchWorkItem?
    static let lifetime: TimeInterval = 3.5

    func show(below closedHeight: CGFloat, content: (NotchTrackPillModel) -> AnyView) {
        hide(animated: false)
        guard let screen = NSScreen.main else { return }
        let model = NotchTrackPillModel { [weak self] in self?.hide(animated: true) }
        let host = NSHostingView(rootView: content(model))
        let size = host.fittingSize
        host.setFrameSize(size)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - closedHeight - size.height - 4))
        panel.orderFrontRegardless()
        self.panel = panel
        self.model = model
        DispatchQueue.main.async { model.present() }
        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime, execute: work)
    }

    func hide(animated: Bool) {
        dismissWork?.cancel(); dismissWork = nil
        guard let panel, let model else { return }
        self.panel = nil; self.model = nil
        guard animated else { panel.orderOut(nil); return }
        model.retract()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { panel.orderOut(nil) }
    }
}

@MainActor
final class NotchTrackPillModel: ObservableObject {
    @Published var shown = false
    let dismiss: () -> Void
    init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }

    func present() { withAnimation(.spring(response: 0.42, dampingFraction: 1.0)) { shown = true } }
    func retract() { withAnimation(.easeIn(duration: 0.28)) { shown = false } }
}

struct NotchTrackPillView: View {
    @ObservedObject var model: NotchTrackPillModel
    @ObservedObject private var feed = LiveActivityFeed.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = feed.nowPlayingState
        let accent = ArtworkAccentCache.accent(for: state.artworkData).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .white
        HStack(spacing: 10) {
            Group {
                if let data = state.artworkData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.12).overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.7)))
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(text: state.title ?? "", font: .system(size: 12, weight: .bold, design: .rounded))
                MarqueeText(text: state.artist ?? "", font: .system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: 170, alignment: .leading)
            MusicEqualizerBars(isActive: state.isPlaying && !reduceMotion, tint: accent)
                .frame(width: 18, height: 16)
        }
        .foregroundStyle(.white)
        .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 7)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().stroke(accent.opacity(0.35), lineWidth: 1))
        .shadow(color: accent.opacity(0.35), radius: 10)
        .padding(14)
        .scaleEffect(model.shown ? 1 : 0.5, anchor: .top)
        .offset(y: model.shown ? 0 : -18)
        .opacity(model.shown ? 1 : 0)
        .contentShape(Capsule())
        .onTapGesture { model.dismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: [state.title, state.artist].compactMap { $0 }.joined(separator: " — ")))
    }
}

/// 51d: a connected device has dropped to a low charge.
struct NotchBatteryPillView: View {
    @ObservedObject var model: NotchTrackPillModel
    let device: BluetoothDevice

    var body: some View {
        let level = device.lowestBattery ?? 0
        HStack(spacing: 8) {
            Image(systemName: device.symbolName).font(.system(size: 13, weight: .semibold))
            Text(verbatim: device.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1).frame(maxWidth: 150)
            Text(verbatim: "\(level)%").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.red)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().stroke(Color.red.opacity(0.4), lineWidth: 1))
        .padding(14)
        .scaleEffect(model.shown ? 1 : 0.5, anchor: .top)
        .offset(y: model.shown ? 0 : -18)
        .opacity(model.shown ? 1 : 0)
        .contentShape(Capsule())
        .onTapGesture { model.dismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(device.name) battery \(level)%"))
    }
}

/// Four bars that dance while music plays and rest flat otherwise (also the Reduce Motion path).
struct MusicEqualizerBars: View {
    let isActive: Bool
    var tint: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let wave = isActive ? 0.35 + 0.65 * abs(sin(t * (2.1 + Double(i) * 0.7) + Double(i))) : 0.25
                    Capsule().fill(tint).frame(width: 2.5, height: 16 * wave)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}
