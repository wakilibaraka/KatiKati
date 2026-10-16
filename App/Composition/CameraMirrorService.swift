import AVFoundation
import Foundation

/// Phase 47b — the live camera behind the notch's mirror page.
///
/// The page is the only thing that holds the camera: `start()` runs when the page appears, `stop()` when
/// it goes away (another page, a collapsed notch, the switch off), so a machine that never opens the page
/// never turns the camera on. The first run raises macOS's camera prompt — this app's first camera ask,
/// which is why `Resources/Info.plist` carries `NSCameraUsageDescription`.
@MainActor
final class CameraMirrorService: ObservableObject {
    static let shared = CameraMirrorService()
    /// The notch page's own switch; the page exists only while it is on.
    static let enabledKey = "com.katikati.notch.mirror"
    private static let selectionKey = "com.katikati.notch.mirror.camera"

    let session = AVCaptureSession()

    @Published private(set) var devices: [CameraMirrorDevice] = []
    @Published private(set) var selection: String =
        UserDefaults.standard.string(forKey: CameraMirrorService.selectionKey) ?? ""
    @Published private(set) var availability: CameraMirrorRules.Availability = .noCameras

    private var input: AVCaptureDeviceInput?
    private var isRunning = false

    private init() {}

    /// What the system offers: the built-in camera, anything external, and Continuity's iPhone/Desk View.
    func refresh() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        )
        devices = discovery.devices.map { CameraMirrorDevice(id: $0.uniqueID, name: $0.localizedName) }
        selection = CameraMirrorRules.resolvedSelection(stored: selection, available: devices)
        availability = CameraMirrorRules.availability(deviceCount: devices.count, authorized: Self.isAuthorized)
    }

    /// Follow another camera. The page calls this straight from the dropdown; the choice is remembered.
    func select(_ id: String) {
        guard selection != id else { return }
        selection = id
        UserDefaults.standard.set(id, forKey: Self.selectionKey)
        guard isRunning else { return }
        run()
    }

    /// Called when the page appears. Asks for the camera the first time, and does nothing while refused.
    func start() {
        refresh()
        guard availability == .ready else { return }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    self.refresh()
                    if granted { self.run() }
                }
            }
            return
        }
        run()
    }

    /// Called when the page goes away: the camera light goes out with it.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    /// "Not asked yet" counts as available: `start()` is the one place that raises the prompt.
    private static var isAuthorized: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .authorized || status == .notDetermined
    }

    private static func device(for id: String) -> AVCaptureDevice? {
        guard !id.isEmpty else { return AVCaptureDevice.default(for: .video) }
        return AVCaptureDevice(uniqueID: id) ?? AVCaptureDevice.default(for: .video)
    }

    private func run() {
        guard let device = Self.device(for: selection) else {
            availability = .noCameras
            return
        }
        session.beginConfiguration()
        if let input { session.removeInput(input) }
        guard let opened = try? AVCaptureDeviceInput(device: device), session.canAddInput(opened) else {
            // The camera is there but would not open — in use by another app, or the grant went away.
            session.commitConfiguration()
            input = nil
            availability = .noCameras
            return
        }
        session.addInput(opened)
        input = opened
        session.sessionPreset = .high
        session.commitConfiguration()
        availability = .ready
        guard !isRunning else { return }
        isRunning = true
        // `startRunning` blocks until the camera is warm: never on the main thread, or the notch freezes.
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }
}
