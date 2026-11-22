import AVFoundation
import AppKit
import SwiftUI

// Camera Check-In & Meeting Preflight page: live mirror preview on the left, camera/mic/speaker/brightness
// controls in the center, and next meeting / call status check-in on the right. Shown by default; the
// camera session activates only while this page is visible — see `CameraMirrorService`.

struct NotchMirrorPageView: View {
    @ObservedObject private var mirror = CameraMirrorService.shared
    @ObservedObject private var toggles = QuickToggleEngine.shared
    @ObservedObject private var agenda = ProductivityServices.shared.calendar
    /// The running-app census behind the call-platform chip. Read off the render pass: LaunchServices
    /// answers slowly enough to hold the page swap while it does.
    @State private var runningBundleIDs: [String] = []

    var body: some View {
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            // NP-4: the floating mic button over the preview was a second Mute next to the card's own.
            content
                .aspectRatio(1, contentMode: .fit)
            MeetingControlsCard(mirror: mirror, cameraName: currentName)
            meetingCheckInCard
        }
        .onAppear {
            // Only the cheap part runs before the first frame: `mirror.start()` hands the camera to its
            // own lane and returns, so the swap is never waiting on a device opening.
            mirror.start()
            toggles.refresh()
        }
        .task {
            // Everything that talks to EventKit or LaunchServices begins after the frame that carries
            // the swap; each of those calls blocks the main thread for its own moment.
            agenda.startEvents()
            runningBundleIDs = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        }
        .onDisappear { mirror.stop() }
    }

    /// Right pane: next calendar event / detected call platform + one-click Join Session or Open Calendar.
    private var meetingCheckInCard: some View {
        let now = Date()
        let activePlatform = MeetingDetectionPolicy.detectPlatform(fromRunningBundleIDs: runningBundleIDs)
        let upcomingEvent = agenda.events
            .sorted { $0.start < $1.start }
            .first { $0.end >= now } ?? agenda.events.first

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(mirror.availability == .ready ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(verbatim: (activePlatform?.displayName ?? "CHECK-IN").uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 0)
                if let platform = activePlatform {
                    Image(systemName: platform.sfSymbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Text(verbatim: now.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if let event = upcomingEvent {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: event.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(verbatim: event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Ready for Calls")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(verbatim: now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button {
                if let event = upcomingEvent {
                    AgendaEventOpener.open(event)
                } else if let url = AgendaEventAction.calendarURL(for: now) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: upcomingEvent?.isJoinable == true ? "video.fill" : "calendar")
                        .font(.system(size: 10, weight: .bold))
                    Text(verbatim: upcomingEvent?.isJoinable == true ? "Join Session" : (upcomingEvent != nil ? "Open Event" : "Open Calendar"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchCard()
    }

    @ViewBuilder
    private var content: some View {
        switch mirror.availability {
        case .ready:
            CameraMirrorPreview(session: mirror.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // NP-4: the preview wears the same 18 pt radius and rim weight as the two cards beside
                // it; at 10 pt with a 0.12 rim it read as a different kind of object.
                .clipShape(RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: 1)
                )
                // The layer is mounted from the start so frames appear the moment the session runs; the
                // warm-up pane only covers it until then.
                .overlay { if mirror.isStarting { opening } }
        case .noCameras:
            // The page swaps first and the camera opens behind it, so the first moment is a warm-up, not a
            // verdict: "No Camera Found" would be a lie on every visit where there is one.
            if mirror.isStarting { opening } else { message(Text("No Camera Found"), door: false) }
        case .denied:
            message(Text("Camera Access Is Off"), door: true)
        }
    }

    /// Warm-up pane for the moment between the page swap and the camera being open.
    private var opening: some View {
        RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(ProgressView().controlSize(.small).tint(.white.opacity(0.45)))
            .overlay(
                RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: 1)
            )
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

/// The middle pane: Mute toggle, Camera switcher, Mic & Audio Output pickers, and screen brightness.
private struct MeetingControlsCard: View {
    @ObservedObject var mirror: CameraMirrorService
    let cameraName: String
    @ObservedObject private var toggles = QuickToggleEngine.shared
    @State private var inputs: [AudioOutputDevice] = []
    @State private var brightness: Double?

    private var muted: Bool { toggles.states[.muteMic] ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { toggles.perform(.muteMic) } label: {
                HStack(spacing: 6) {
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                    Text(verbatim: muted ? "Unmute" : "Mute")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(Capsule().fill(muted ? Color.red.opacity(0.85) : Color.white.opacity(0.14)))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            cameraPicker
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
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchCard()
        .task {
            // CoreAudio's device list is a synchronous HAL query: it fills in after the swap has drawn.
            brightness = DisplayServicesBrightness.current()
            inputs = await Task.detached(priority: .userInitiated) {
                AudioOutputSwitcher.devices(input: true)
            }.value
        }
    }

    @ViewBuilder
    private var cameraPicker: some View {
        if mirror.devices.count > 1 {
            Menu {
                Button(String(localized: "System Default")) { mirror.select("") }
                Divider()
                ForEach(mirror.devices, id: \.id) { device in
                    Button(device.name) { mirror.select(device.id) }
                }
            } label: {
                row("camera.viewfinder", Text(verbatim: cameraName))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text("Choose Camera"))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "camera.viewfinder").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).frame(width: 14)
                Text(verbatim: cameraName).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
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
