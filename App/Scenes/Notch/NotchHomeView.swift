import AppKit
import SwiftUI

/// Open state of the full notch skin: header row on top, flanked by the configurable Notch Page Roster,
/// then the active Bento Page (AI, Music, Calendar, Storage, Downloads, Teleprompter, Camera Check-in,
/// Studio Hub, Keep Awake). The page slide follows the paging direction;
/// reduced-motion falls back to a plain fade.
struct NotchHomeView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var feed: LiveActivityFeed
    let metrics: NotchMetrics
    let calendarEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let forward = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity))
    static let backward = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity))

    var body: some View {
        VStack(spacing: 0) {
            // 59d: the battery card hangs out of the header, so the header must draw above the page.
            NotchHeaderView(model: model, metrics: metrics)
                .zIndex(1)

            Group {
                switch model.activePage {
                case .aiTracker:
                    NotchAIPageView()
                case .audioDeck:
                    NotchMusicPageView(feed: feed)
                case .calendar:
                    NotchProductivityPageView(feed: feed)
                case .peripherals:
                    NotchPeripheralsPageView()
                case .teleprompter:
                    NotchTeleprompterPageView()
                case .cameraMirror:
                    NotchMirrorPageView()
                case .studioHub:
                    NotchToolsView()
                case .keepAwake:
                    NotchKeepAwakePageView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 4)
            .transition(reduceMotion ? .opacity : (model.pageDirection >= 0 ? Self.forward : Self.backward))
            .id(model.activePage)
        }
        // Inset by flaring top ear radius and horizontal grid padding
        .padding(.horizontal, NotchDesignSpec.openCornerRadii.topFlaring + NotchDesignSpec.gridPadding.leading)
        .padding(.bottom, NotchDesignSpec.gridPadding.bottom)
    }
}

/// NP-2: the open notch's one card. Every page wears the same 0.10 white fill, 1 pt 0.08 rim and 18 pt
/// continuous radius, so no page can invent its own tint, border or radius. 0.10 is deliberate: 0.06 let
/// desktop text read through the cards (live-checked 2026-10-17).
struct NotchCardSurface: ViewModifier {
    var fillOpacity: Double = NotchDesignSpec.cardFillOpacity
    var strokeOpacity: Double = NotchDesignSpec.cardStrokeOpacity

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
        return content
            .background(
                shape.fill(Color.white.opacity(fillOpacity))
                    .overlay(shape.strokeBorder(Color.white.opacity(strokeOpacity),
                                                lineWidth: NotchDesignSpec.cardStrokeWidth))
            )
    }
}

extension View {
    /// The one card surface every notch page draws.
    func notchCard() -> some View { modifier(NotchCardSurface()) }
}

/// DockSet-style Peripherals & AirPods hub inside the Notch: Mac battery + active audio output hero
/// on the left, connected Bluetooth battery breakdown list + platform boundary note on the right.
struct NotchPeripheralsPageView: View {
    @ObservedObject private var telemetry = DockTelemetryFeed.shared
    @ObservedObject private var devicesFeed = DockDevicesFeed.shared
    @State private var audioOutputs: [AudioOutputDevice] = []

    private var overview: DockPeripheralBatteryOverview {
        DockPeripheralBatteryOverview.build(
            macPercent: telemetry.state.batteryFraction.map { Int(($0 * 100).rounded()) },
            macCharging: telemetry.state.batteryCharging,
            macOnAC: telemetry.state.batteryFraction == nil || telemetry.state.batteryCharging,
            devices: devicesFeed.devices
        )
    }

    var body: some View {
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            heroCard
                .frame(width: 178)
                .frame(maxHeight: .infinity)
                .notchCard()

            peripheralsListCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .notchCard()
        }
        .onAppear {
            telemetry.retain()
            devicesFeed.retain()
            audioOutputs = AudioOutputSwitcher.devices()
        }
        .onDisappear {
            telemetry.release()
            devicesFeed.release()
        }
    }

    private var heroCard: some View {
        let macTint = batteryColor(overview.macPercent, charging: overview.macCharging)
        let activeAudio = audioOutputs.first(where: \.isDefault)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: overview.macPercent == nil ? "desktopcomputer" : "laptopcomputer")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("This Mac")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    devicesFeed.refreshNow()
                    audioOutputs = AudioOutputSwitcher.devices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(devicesFeed.isRefreshing ? 0.38 : 0.72))
                }
                .buttonStyle(.plain)
                .disabled(devicesFeed.isRefreshing)
                .accessibilityLabel(Text("Refresh"))
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: overview.macPercent.map { "\($0)%" } ?? "AC")
                    .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                if overview.macCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                }
                if let watts = telemetry.state.batteryWatts {
                    Text(verbatim: String(format: "%.0fW", watts))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.60))
                }
            }

            miniBar(fraction: Double(overview.macPercent ?? 100) / 100.0, tint: macTint)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Menu {
                    ForEach(audioOutputs) { output in
                        Button {
                            AudioOutputSwitcher.setDefault(output.id)
                            audioOutputs = AudioOutputSwitcher.devices()
                        } label: {
                            if output.isDefault {
                                Label(output.name, systemImage: "checkmark")
                            } else {
                                Text(verbatim: output.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "airplayaudio")
                            .font(.system(size: 10, weight: .semibold))
                        Text(verbatim: activeAudio?.name ?? String(localized: "Audio Output"))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.70))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Bluetooth Settings"))
            }
        }
        .padding(NotchDesignSpec.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var peripheralsListCard: some View {
        let activeAudioName = audioOutputs.first(where: \.isDefault)?.name
        return VStack(alignment: .leading, spacing: 5) {
            if overview.connectedPeripherals.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "airpodspro")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.42))
                    Text("No Bluetooth peripherals connected")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(overview.connectedPeripherals) { device in
                            let isAudioActive = device.isAudioPeripheral && (activeAudioName?.localizedCaseInsensitiveCompare(device.name) == .orderedSame)
                            HStack(spacing: 8) {
                                Image(systemName: device.richSymbolName)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(batteryColor(device.lowestBattery))
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(verbatim: device.name)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        if isAudioActive {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    if let breakdown = device.batteryBreakdown {
                                        Text(verbatim: breakdown)
                                            .font(.system(size: 9, design: .rounded).monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.55))
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 4)

                                if let level = device.lowestBattery {
                                    miniBar(fraction: Double(level) / 100.0, tint: batteryColor(level))
                                        .frame(width: 32)
                                    Text(verbatim: "\(level)%")
                                        .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(batteryColor(level))
                                        .frame(minWidth: 30, alignment: .trailing)
                                } else {
                                    Text("Connected")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                    }
                }
            }

            Text("Shows Mac and Bluetooth accessories. macOS does not share iPhone or Apple Watch battery levels with third-party apps.")
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(2)
        }
        .padding(NotchDesignSpec.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func miniBar(fraction: Double, tint: Color) -> some View {
        let clamped = min(max(fraction, 0), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(Color.white.opacity(0.14))
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(4, geo.size.width * CGFloat(clamped)))
            }
        }
        .frame(height: 4)
    }

    private func batteryColor(_ percent: Int?, charging: Bool = false) -> Color {
        if charging { return .green }
        guard let percent else { return .white.opacity(0.65) }
        if percent <= 20 { return .red }
        if percent <= 40 { return .orange }
        return .green
    }
}
