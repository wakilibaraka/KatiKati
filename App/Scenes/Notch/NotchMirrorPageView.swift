import AVFoundation
import AppKit
import SwiftUI

// Phase 47b — the optional 8th notch page: a live camera mirror, with the camera chosen from a dropdown
// on the page itself. Off by default (`com.katikati.notch.mirror`), and the camera runs only while this
// page is on screen — see `CameraMirrorService`.

struct NotchMirrorPageView: View {
    @ObservedObject private var mirror = CameraMirrorService.shared

    var body: some View {
        VStack(spacing: 8) {
            header
            content
        }
        .padding(NotchDesignSpec.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
        )
        .onAppear { mirror.start() }
        .onDisappear { mirror.stop() }
    }

    /// The camera in use on the left, the picker on the right: one row, so the preview keeps the height.
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(verbatim: currentName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                    HStack(spacing: 4) {
                        Text("Choose Camera").font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
