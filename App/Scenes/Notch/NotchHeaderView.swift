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
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = false
    @AppStorage(CameraMirrorService.enabledKey) private var cameraMirrorPage = true
    @AppStorage(NotchPageLayout.defaultsKey) private var pageLayoutRaw = ""   // re-renders the roster
    /// 59d: the battery card hangs under the chip, over the page area. Read-only, so it never takes a
    /// click the page wanted; the chip's own tap toggles it.
    @State private var showsBatteryDetail = false
    @AppStorage(NotchHUDPresentation.showWhenOpenKey) private var showOpenHUD = true
    @AppStorage(NotchHUDPresentation.showPercentageKey) private var showHUDPercentage = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pages: [NotchPage] {
        NotchPage.visible(teleprompter: teleprompterPage, mirror: cameraMirrorPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                pageIcons.fixedSize(horizontal: true, vertical: false)
                ScrollView(.horizontal) { pageIcons }
                    .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if metrics.hasHardwareNotch {
                Color.clear.frame(width: metrics.closedSize.width).accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                if pages.contains(.cameraMirror) { tab(.cameraMirror) }
                if showOpenHUD, let hud = model.activeHUDItem, let level = hud.level {
                    Label {
                        ProgressView(value: level)
                            .progressViewStyle(.linear)
                            .frame(width: 38)
                    } icon: {
                        Image(systemName: hud.icon)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityLabel(Text(verbatim: hud.title))
                    if showHUDPercentage {
                        Text(level, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    }
                } else {
                    volume
                    if let level = power.status.battery.level { battery(level) }
                }
                gearButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .frame(height: NotchLayoutSpec.headerHeight(closedHeight: metrics.closedSize.height))
        .onAppear { power.acquire() }
        .onDisappear { power.release() }
    }

    private func tab(_ page: NotchPage) -> some View {
        let selected = model.activePage.navigationPage == page
        return Button { select(page) } label: {
            Image(systemName: page.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: page == .cameraMirror ? 24 : 26, height: 26)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0)))
                .foregroundStyle(selected ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: page.title))
        .help(Text(verbatim: page.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var pageIcons: some View {
        HStack(spacing: 2) {
            ForEach(pages.filter { $0 != .cameraMirror }) { page in tab(page) }
        }
    }

    private func select(_ page: NotchPage) {
        let spring = NotchMotionSpec.pageStepSpring
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: spring.response, dampingFraction: spring.dampingRatio)) {
            model.goToPage(page)
        }
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
