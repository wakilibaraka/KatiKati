import AVFoundation
import AppKit
import SwiftUI

// Phase 47b — the optional 8th notch page: a live camera mirror, with the camera chosen from a dropdown
// on the page itself. Off by default (`com.katikati.notch.mirror`), and the camera runs only while this
// page is on screen — see `CameraMirrorService`.

struct NotchMirrorPageView: View {
    @ObservedObject private var mirror = CameraMirrorService.shared

    var body: some View {
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            clockCard
            MeetingControlsCard()
            content
                .aspectRatio(1, contentMode: .fit)
        }
        .onAppear { mirror.start() }
        .onDisappear { mirror.stop() }
    }

    /// Time and date on the left (the rail tile's 12/24-hour rule), with the camera name and picker below.
    private var clockCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: ClockTick.nextMinute(after: Date()), by: 60)) { context in
                let parts = RailClockTile.hourMinute(context.date)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(parts.hour):\(parts.minute)")
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(verbatim: context.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            header
        }
        .padding(NotchDesignSpec.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
        )
    }

    /// The camera in use, with the picker beside it.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(verbatim: currentName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            if mirror.devices.count > 1 {
                Menu {
                    Button(String(localized: "System Default")) { mirror.select("") }
                    Divider()
                    ForEach(mirror.devices, id: \.id) { device in
                        Button(device.name) { mirror.select(device.id) }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(Text("Choose Camera"))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mirror.availability {
        case .ready:
            CameraMirrorPreview(session: mirror.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        case .noCameras:
            message(Text("No Camera Found"), door: false)
        case .denied:
            message(Text("Camera Access Is Off"), door: true)
        }
    }

    private func message(_ text: Text, door: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            text
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            if door {
                Button(String(localized: "Open System Settings")) {
                    if let url = CameraMirrorRules.cameraSettingsURL { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentName: String {
        mirror.devices.first { $0.id == mirror.selection }?.name ?? String(localized: "System Default")
    }
}

/// The middle pane: what you reach for in a Zoom or Meet call — mute, which mic and speaker, screen brightness.
private struct MeetingControlsCard: View {
    @ObservedObject private var toggles = QuickToggleEngine.shared
    @State private var inputs: [AudioOutputDevice] = []
    @State private var brightness: Double?

    private var muted: Bool { toggles.states[.muteMic] ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { toggles.perform(.muteMic) } label: {
                HStack(spacing: 6) {
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                    Text(muted ? "Unmute" : "Mute")
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(Capsule().fill(muted ? Color.red.opacity(0.85) : Color.white.opacity(0.14)))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            micPicker
            AudioOutputMenu {
                row("speaker.wave.2.fill", Text("Audio Output"))
            }
            if let level = brightness {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                    Slider(value: Binding(get: { level }, set: { brightness = $0; DisplayServicesBrightness.set($0) }), in: 0.05...1)
                        .controlSize(.mini)
                        .accessibilityLabel(Text(verbatim: "Brightness"))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(NotchDesignSpec.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
        )
        .onAppear {
            toggles.refresh()
            inputs = AudioOutputSwitcher.devices(input: true)
            brightness = DisplayServicesBrightness.current()
        }
    }

    private var micPicker: some View {
        Menu {
            ForEach(inputs) { device in
                Button {
                    AudioOutputSwitcher.setDefault(device.id, input: true)
                    inputs = AudioOutputSwitcher.devices(input: true)
                } label: {
                    if device.isDefault { Label(device.name, systemImage: "checkmark") } else { Text(verbatim: device.name) }
                }
            }
        } label: {
            row("waveform", Text(verbatim: inputs.first { $0.isDefault }?.name ?? "Microphone"))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ symbol: String, _ title: Text) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).frame(width: 14)
            title.font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

/// The session's own preview layer, mirrored so the picture reads as a mirror rather than as a camera —
/// which is the whole point of the feature (`isVideoMirrored` on the layer's own connection).
private struct CameraMirrorPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> MirrorPreviewView {
        let view = MirrorPreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: MirrorPreviewView, context: Context) {
        if view.previewLayer.session !== session { view.previewLayer.session = session }
    }
}

private final class MirrorPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        // Set on every layout: the connection only exists once the session has an input, and the session
        // is configured after this view is built.
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
