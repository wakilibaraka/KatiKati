import AppKit
import SwiftUI

/// Header row of the full notch skin: tabs (Home, Shelf) on the left of the hardware notch, settings
/// and battery on the right. The middle stays empty so the notch itself is never drawn over.
struct NotchHeaderView: View {
    @ObservedObject var model: NotchModel
    let metrics: NotchMetrics
    @StateObject private var power = SystemStatusService()
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = false
    @AppStorage(CameraMirrorService.enabledKey) private var cameraMirrorPage = false
    @AppStorage(NotificationMirrorService.enabledKey) private var notificationsPage = false
    @AppStorage(NotchPageLayout.defaultsKey) private var pageLayoutRaw = ""   // re-renders the page strip
    /// 59d: the battery card hangs under the chip, over the page area. Read-only, so it never takes a
    /// click the page wanted; the chip's own tap toggles it.
    @State private var showsBatteryDetail = false

    var body: some View {
        let side = NotchLayoutSpec.headerButtonSize
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(NotchPage.visible(teleprompter: teleprompterPage, mirror: cameraMirrorPage,
                                          notifications: notificationsPage)) { page in
                    pageButton(page)
                }
            }
            Spacer(minLength: metrics.closedSize.width)
            HStack(spacing: NotchLayoutSpec.headerSpacing) {
                volume
                if let level = power.status.battery.level {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { showsBatteryDetail.toggle() }
                    } label: {
                        NotchBatteryChip(level: level, battery: power.status.battery, scale: 1.25)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        if showsBatteryDetail {
                            NotchBatteryDetail(level: level, battery: power.status.battery)
                                .offset(y: NotchLayoutSpec.headerHeight(closedHeight: metrics.closedSize.height) + 6)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                }
                Button { model.collapse(); model.openSettings() } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 12, weight: .semibold))
                        .frame(width: side, height: side)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: "KatiKati Settings"))
            }
        }
        .foregroundStyle(.white)
        .frame(height: NotchLayoutSpec.headerHeight(closedHeight: metrics.closedSize.height))
        .onAppear { power.acquire() }
        .onDisappear { power.release() }
    }

    /// Compact output-volume control: speaker glyph (tap = mute toggle is left to the system) + slider.
    private var volume: some View {
        HStack(spacing: 4) {
            Image(systemName: power.status.volume.isMuted || power.status.volume.level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                .frame(width: 16)
            Slider(value: Binding(get: { Double(power.status.volume.level) },
                                  set: { _ = power.setVolume(Float($0)) }), in: 0...1)
                .controlSize(.mini)
                .frame(width: NotchLayoutSpec.volumeSliderWidth)
        }
        .padding(.trailing, 4)
    }

    private func pageButton(_ page: NotchPage) -> some View {
        let selected = model.activePage == page
        let side: CGFloat = 24
        return Button {
            withAnimation(.spring(response: NotchMotionSpec.pageStepSpring.response, dampingFraction: NotchMotionSpec.pageStepSpring.dampingRatio)) {
                model.goToPage(page)
            }
        } label: {
            Image(systemName: page.symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: side, height: side)
                .background(Circle().fill(Color.white.opacity(selected ? 0.24 : 0.0)))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.5))
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: page.title))
    }

    static func batterySymbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
