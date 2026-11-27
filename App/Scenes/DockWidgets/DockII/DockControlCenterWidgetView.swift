import AppKit
import SwiftUI

/// DeXign Studio Dock II Control Center Quick Toggles & Brightness/Volume wing widget.
/// Uses `QuickToggleEngine`, `DisplayServicesBrightness`, and `SystemStatusService`.
struct DockControlCenterWidgetView: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockWingVertical) private var isVertical
    @Environment(\.dockPopoverEdge) private var popoverEdge
    @ObservedObject private var toggles = QuickToggleEngine.shared
    @StateObject private var systemStatus = SystemStatusService()
    @State private var showSliderCard = false
    @State private var brightness: Double = DisplayBrightness.levelForCursorScreen() ?? 0.75
    /// MD-5: the external panel's own volume; nil when it does not answer VCP `0x62`.
    @State private var displayVolume: Double?
    @State private var keyLight: Double? = KeyboardBacklight.current()
    private let brightnessAvailable = DisplayBrightness.levelForCursorScreen() != nil

    private let airplayGreen = Color(red: 0.25, green: 0.85, blue: 0.45)
    private let bluetoothCyan = Color(red: 0.22, green: 0.75, blue: 0.98)

    var body: some View {
        let wifiOn = toggles.states[.wifi] ?? false
        let btOn = toggles.states[.bluetooth] ?? false
        let vol = Double(systemStatus.currentVolumeLevel)

        Group {
            if isVertical { verticalBody(wifiOn: wifiOn, btOn: btOn, vol: vol) }
            else { horizontalBody(wifiOn: wifiOn, btOn: btOn, vol: vol) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .popover(isPresented: $showSliderCard, arrowEdge: popoverEdge) {
            DockControlCenterSliderCard(
                brightness: $brightness,
                brightnessAvailable: brightnessAvailable,
                keyLight: $keyLight,
                volume: Binding(
                    get: { Double(systemStatus.currentVolumeLevel) },
                    set: { systemStatus.setVolume(Float(min(1, max(0, $0)))) }
                ),
                displayVolume: $displayVolume,
                onBrightnessChange: { DisplayBrightness.setOnCursorScreen($0) },
                onDisplayVolumeChange: { DisplayBrightness.setVolumeOnCursorScreen($0) },
                onKeyLightChange: { KeyboardBacklight.set($0) },
                onOpenDisplays: { toggles.perform(.screenMirroring) }
            )
        }
        .onAppear {
            systemStatus.acquire()
            toggles.refresh()
            if let current = DisplayBrightness.levelForCursorScreen() {
                brightness = current
            }
            displayVolume = DisplayBrightness.volumeForCursorScreen()
            keyLight = KeyboardBacklight.current()
        }
        .onDisappear {
            systemStatus.release()
        }
        .onReceive(NotificationCenter.default.publisher(for: DisplayBrightness.didUpdateNotification)) { _ in
            if let current = DisplayBrightness.levelForCursorScreen() {
                brightness = current
            }
            displayVolume = DisplayBrightness.volumeForCursorScreen()
        }
    }

    private func verticalBody(wifiOn: Bool, btOn: Bool, vol: Double) -> some View {
        VStack(spacing: size == .small ? 5 : 6) {
            brightnessButton
            if size != .small { wifiButton(wifiOn); volumeButton(vol) }
            if size == .large { bluetoothButton(btOn) }
        }
        .padding(.vertical, 6)
    }

    private func horizontalBody(wifiOn: Bool, btOn: Bool, vol: Double) -> some View {
        HStack(spacing: size == .small ? 8 : 11) {
            if size != .small {
                glyphButton(symbol: "airplayaudio", tint: airplayGreen, helpText: String(localized: "Display Settings")) {
                    toggles.perform(.screenMirroring)
                }
                .accessibilityLabel(Text("Screen Mirroring"))
            }
            brightnessButton
            wifiButton(wifiOn)
            if size == .large { bluetoothButton(btOn) }
            volumeButton(vol)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var brightnessButton: some View {
        glyphButton(symbol: "sun.max.fill", tint: brightness > 0.05 ? DockWidgetStyle.ink : DockWidgetStyle.ink.opacity(0.45),
                    helpText: String(localized: "Brightness & Volume")) {
            brightness = DisplayBrightness.levelForCursorScreen() ?? brightness
            keyLight = KeyboardBacklight.current()
            showSliderCard.toggle()
        }
        .accessibilityLabel(Text("Brightness"))
    }

    private func wifiButton(_ on: Bool) -> some View {
        glyphButton(symbol: on ? "wifi" : "wifi.slash", tint: on ? DockWidgetStyle.ink : DockWidgetStyle.ink.opacity(0.42),
                    helpText: String(localized: "Wi-Fi")) { toggles.perform(.wifi) }
            .accessibilityLabel(Text("Wi-Fi"))
    }

    private func bluetoothButton(_ on: Bool) -> some View {
        Button { toggles.perform(.bluetooth) } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.10)).frame(width: 26, height: 26)
                BluetoothGlyph(side: 13, color: on ? bluetoothCyan : DockWidgetStyle.ink.opacity(0.42))
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text("Bluetooth"))
        .accessibilityLabel(Text("Bluetooth"))
    }

    private func volumeButton(_ vol: Double) -> some View {
        glyphButton(symbol: volumeSymbol(for: vol), tint: vol > 0.01 ? DockWidgetStyle.ink : DockWidgetStyle.ink.opacity(0.42),
                    helpText: String(localized: "Volume & Brightness")) {
            brightness = DisplayBrightness.levelForCursorScreen() ?? brightness
            keyLight = KeyboardBacklight.current()
            showSliderCard.toggle()
        }
        .accessibilityLabel(Text("Volume"))
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
    @Binding var keyLight: Double?
    @Binding var volume: Double
    /// MD-5: the external display's own volume, nil when the panel does not answer DDC `0x62`.
    @Binding var displayVolume: Double?
    let onBrightnessChange: (Double) -> Void
    let onDisplayVolumeChange: (Double) -> Void
    let onKeyLightChange: (Double) -> Void
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

                if let currentDisplayVolume = displayVolume {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Display Volume").font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(verbatim: "\(Int((currentDisplayVolume * 100).rounded()))%")
                                .dockCaption()
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { currentDisplayVolume },
                                    set: {
                                        displayVolume = $0
                                        onDisplayVolumeChange($0)
                                    }
                                ),
                                in: 0...1.0
                            )
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 13))
                        }
                    }
                }

                if let currentKeyLight = keyLight {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Keyboard").font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(verbatim: "\(Int((currentKeyLight * 100).rounded()))%")
                                .dockCaption()
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "light.min")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { currentKeyLight },
                                    set: {
                                        keyLight = $0
                                        onKeyLightChange($0)
                                    }
                                ),
                                in: 0...1.0
                            )
                            Image(systemName: "keyboard")
                                .font(.system(size: 13))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Sound").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        AudioOutputMenu {
                            Image(systemName: "airplayaudio")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
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
