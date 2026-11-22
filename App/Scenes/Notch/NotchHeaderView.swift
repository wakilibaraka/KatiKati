import AppKit
import SwiftUI

/// Header row of the full notch skin: one page capsule left of the hardware notch, volume, battery and
/// settings right of it. The middle stays empty so the notch itself is never drawn over.
///
/// NP-2 replaced nine 19 pt icon buttons (10 pt glyphs, names only in a `help` bubble) with one capsule
/// that names the page it is on and opens the same roster. The duplicate dot strip under the page is gone.
struct NotchHeaderView: View {
    @ObservedObject var model: NotchModel
    let metrics: NotchMetrics
    @StateObject private var power = SystemStatusService()
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = true
    @AppStorage(CameraMirrorService.enabledKey) private var cameraMirrorPage = true
    @AppStorage(NotchPageLayout.defaultsKey) private var pageLayoutRaw = ""   // re-renders the roster
    /// 59d: the battery card hangs under the chip, over the page area. Read-only, so it never takes a
    /// click the page wanted; the chip's own tap toggles it.
    @State private var showsBatteryDetail = false

    private var pages: [NotchPage] {
        NotchPage.visible(teleprompter: teleprompterPage, mirror: cameraMirrorPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            pagePill
            Spacer(minLength: metrics.closedSize.width)
            HStack(spacing: 6) {
                volume
                if let level = power.status.battery.level {
                    battery(level)
                }
                gearButton
            }
        }
        .foregroundStyle(.white)
        .frame(height: NotchLayoutSpec.headerHeight(closedHeight: metrics.closedSize.height))
        .onAppear { power.acquire() }
        .onDisappear { power.release() }
    }

    /// One capsule for the whole roster: the active page's glyph and name, a chevron, and a menu holding
    /// every visible page in paging order. The title is still and shrinks before it truncates.
    private var pagePill: some View {
        Menu {
            ForEach(pages) { page in
                Button {
                    withAnimation(.spring(response: NotchMotionSpec.pageStepSpring.response,
                                          dampingFraction: NotchMotionSpec.pageStepSpring.dampingRatio)) {
                        model.goToPage(page)
                    }
                } label: {
                    Label(page.title, systemImage: model.activePage == page ? "checkmark" : page.symbol)
                }
            }
        } label: {
            HStack(spacing: NotchPageChrome.pillSpacing) {
                Image(systemName: model.activePage.symbol)
                    .font(.system(size: NotchPageChrome.pillIcon, weight: .semibold))
                Text(verbatim: model.activePage.title)
                    .font(.system(size: NotchPageChrome.pillTitleSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: NotchPageChrome.pillMaxTitleWidth, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: NotchPageChrome.pillChevron, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, NotchPageChrome.pillHorizontalPadding)
            .frame(height: NotchPageChrome.pillHeight)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .fixedSize()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text(verbatim: "Switch notch page"))
    }

    private func battery(_ level: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showsBatteryDetail.toggle() }
        } label: {
            NotchBatteryChip(level: level, battery: power.status.battery, scale: 1.15)
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

    private var gearButton: some View {
        let side = min(NotchLayoutSpec.headerButtonSize, 22)
        return Button { model.collapse(); model.openSettings() } label: {
            Image(systemName: "gearshape.fill").font(.system(size: 11, weight: .semibold))
                .frame(width: side, height: side)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: "KatiKati Settings"))
    }

    /// Compact output-volume control: speaker glyph + compact slider sized to avoid pushing the gear off-edge.
    private var volume: some View {
        HStack(spacing: 3) {
            Image(systemName: power.status.volume.isMuted || power.status.volume.level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                .frame(width: 14)
            Slider(value: Binding(get: { Double(power.status.volume.level) },
                                  set: { _ = power.setVolume(Float($0)) }), in: 0...1)
                .controlSize(.mini)
                .frame(width: min(NotchLayoutSpec.volumeSliderWidth, 46))
        }
        .padding(.trailing, 2)
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
