import AppKit
import SwiftUI

/// DeXign Studio Dock II Control Center Quick Toggles & Brightness/Volume wing widget.
/// Uses `QuickToggleEngine`, `DisplayServicesBrightness`, and `SystemStatusService`.
struct DockControlCenterWidgetView: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockPopoverEdge) private var popoverEdge
    @ObservedObject private var toggles = QuickToggleEngine.shared
    @StateObject private var systemStatus = SystemStatusService()
    @State private var showSliderCard = false
    @State private var brightness: Double = DisplayServicesBrightness.current() ?? 0.75
    private let brightnessAvailable = DisplayServicesBrightness.current() != nil

    private let airplayGreen = Color(red: 0.25, green: 0.85, blue: 0.45)
    private let bluetoothCyan = Color(red: 0.22, green: 0.75, blue: 0.98)

    var body: some View {
        let wifiOn = toggles.states[.wifi] ?? false
        let btOn = toggles.states[.bluetooth] ?? false
        let vol = Double(systemStatus.currentVolumeLevel)

        HStack(spacing: size == .small ? 8 : 11) {
            if size != .small {
                glyphButton(
                    symbol: "airplayaudio",
                    tint: airplayGreen,
                    helpText: String(localized: "Display Settings")
                ) {
                    toggles.perform(.screenMirroring)
                }
                .accessibilityLabel(Text("Screen Mirroring"))
            }

            glyphButton(
                symbol: "sun.max.fill",
                tint: brightness > 0.05 ? DockWidgetStyle.ink : DockWidgetStyle.ink.opacity(0.45),
                helpText: String(localized: "Brightness & Volume")
            ) {
                brightness = DisplayServicesBrightness.current() ?? brightness
                showSliderCard.toggle()
            }
            .accessibilityLabel(Text("Brightness"))

            glyphButton(
                symbol: wifiOn ? "wifi" : "wifi.slash",
                tint: wifiOn ? DockWidgetStyle.ink : DockWidgetStyle.ink.opacity(0.42),
                helpText: String(localized: "Wi-Fi")
            ) {
                toggles.perform(.wifi)
            }
            .accessibilityLabel(Text("Wi-Fi"))

            if size == .large {
                glyphButton(
                    symbol: "dot.radiowaves.left.and.right",
                    tint: btOn ? bluetoothCyan : DockWidgetStyle.ink.opacity(0.42),
                    helpText: String(localized: "Bluetooth")
                ) {
                    toggles.perform(.bluetooth)
                }
                .accessibilityLabel(Text("Bluetooth"))
            }

            glyphButton(
                symbol: volumeSymbol(for: vol),
                tint: vol > 0.01 ? DockWidgetStyle.ink : DockWidgetStyle.ink.opacity(0.42),
                helpText: String(localized: "Volume & Brightness")
            ) {
                brightness = DisplayServicesBrightness.current() ?? brightness
                showSliderCard.toggle()
            }
            .accessibilityLabel(Text("Volume"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .popover(isPresented: $showSliderCard, arrowEdge: popoverEdge) {
            DockControlCenterSliderCard(
                brightness: $brightness,
                brightnessAvailable: brightnessAvailable,
                volume: Binding(
                    get: { Double(systemStatus.currentVolumeLevel) },
                    set: { systemStatus.setVolume(Float(min(1, max(0, $0)))) }
                ),
                onBrightnessChange: { DisplayServicesBrightness.set($0) },
                onOpenDisplays: { toggles.perform(.screenMirroring) }
            )
        }
        .onAppear {
            systemStatus.acquire()
            toggles.refresh()
            if let current = DisplayServicesBrightness.current() {
                brightness = current
            }
        }
        .onDisappear {
            systemStatus.release()
        }
    }

    private func volumeSymbol(for level: Double) -> String {
        if level <= 0.01 { return "speaker.slash.fill" }
        if level < 0.35 { return "speaker.wave.1.fill" }
        if level < 0.7 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func glyphButton(
        symbol: String,
        tint: Color,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 26, height: 26)
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: helpText))
    }
}

private struct DockControlCenterSliderCard: View {
    @Binding var brightness: Double
    let brightnessAvailable: Bool
    @Binding var volume: Double
    let onBrightnessChange: (Double) -> Void
    let onOpenDisplays: () -> Void

    var body: some View {
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 12) {
                if brightnessAvailable {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Brightness").font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(verbatim: "\(Int((brightness * 100).rounded()))%")
                                .dockCaption()
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "sun.min.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { brightness },
                                    set: {
                                        brightness = $0
                                        onBrightnessChange($0)
                                    }
                                ),
                                in: 0.02...1.0
                            )
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 14))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Sound").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(verbatim: "\(Int((volume * 100).rounded()))%")
                            .dockCaption()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Slider(value: $volume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 13))
                    }
                }

                Divider().opacity(0.25)

                Button(action: onOpenDisplays) {
                    HStack {
                        Text("Display Settings...")
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
