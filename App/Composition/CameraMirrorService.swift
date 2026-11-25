import AVFoundation
import Foundation

/// Phase 47b — the live camera behind the notch's mirror page.
///
/// The page is the only thing that holds the camera: `start()` runs when the page appears, `stop()` when
/// it goes away (another page, a collapsed notch, the switch off), so a machine that never opens the page
/// never turns the camera on. The first run raises macOS's camera prompt — this app's first camera ask,
/// which is why `Resources/Info.plist` carries `NSCameraUsageDescription`.
///
/// None of that happens on the main thread. Discovery, opening the device and `startRunning()` each block
/// for a second or more, and running them from the page's `onAppear` held the notch on the previous page
/// for that whole time. They live on `queue` now: the page swap draws at once and the preview fills in
/// when the camera is warm.
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
    /// True from `start()` until the camera is open (or refused). The page shows a warm-up pane meanwhile
    /// instead of claiming there is no camera.
    @Published private(set) var isStarting = false
    @Published private(set) var isMirrored = false

    private var input: AVCaptureDeviceInput?
    private var isRunning = false
    /// Set by the page appearing, cleared when it goes away: a grant that lands after the owner left must
    /// not turn the camera on.
    private var wantsCamera = false
    /// Bumped by every start/stop/select. Work that finishes under an older number is dropped, so a page
    /// the owner has already left can never start the camera behind them.
    private var generation = 0
    /// The one lane for blocking AVFoundation calls: open the device here, then `startRunning()` here.
    private let queue = DispatchQueue(label: "com.katikati.notch.mirror", qos: .userInitiated)

    private init() {}

    /// What the system offers: the built-in camera, anything external, and Continuity's iPhone/Desk View.
    /// Discovery opens a CMIO connection per camera, so it runs on the camera lane and publishes on main.
    func refresh() {
        let stored = selection
        queue.async { [weak self] in
            let found = Self.discover()
            let resolved = CameraMirrorRules.resolvedSelection(stored: stored, available: found)
            let state = CameraMirrorRules.availability(deviceCount: found.count, authorized: Self.isAuthorized)
            Task { @MainActor in
                guard let self else { return }
                self.devices = found
                self.selection = resolved
                self.availability = state
            }
        }
    }

    /// Follow another camera. The page calls this straight from the dropdown; the choice is remembered.
    func select(_ id: String) {
        guard selection != id else { return }
        selection = id
        UserDefaults.standard.set(id, forKey: Self.selectionKey)
        guard isRunning else { return }
        generation &+= 1
        open(generation: generation)
    }

    /// Called when the page appears. Returns immediately: the camera is opened on the camera lane, so the
    /// notch has already swapped pages by the time the device wakes up.
    func start() {
        wantsCamera = true
        generation &+= 1
        isStarting = true
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            // The welcome pass owns the prompt. After it has run, a page appearing must not raise a
            // second one — the mirror simply reports that the camera is not available.
            guard PermissionBootstrap.mayPromptFromFeature else {
                isStarting = false
                refresh()
                return
            }
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    guard self.wantsCamera else { self.refresh(); return }
                    if granted { self.start() } else { self.isStarting = false; self.refresh() }
                }
            }
            return
        }
        open(generation: generation)
    }

    /// Called when the page goes away: the camera light goes out with it.
    func stop() {
        wantsCamera = false
        generation &+= 1
        isStarting = false
        isMirrored = false
        guard isRunning else { return }
        isRunning = false
        let session = self.session
        queue.async { session.stopRunning() }
    }

    /// Discovery, then the device open and the session configuration, all on the camera lane. Only the
    /// final bookkeeping returns to the main thread, and only if this start is still the current one.
    private func open(generation token: Int) {
        let wanted = selection
        queue.async { [weak self] in
            let found = Self.discover()
            let resolved = CameraMirrorRules.resolvedSelection(stored: wanted, available: found)
            let state = CameraMirrorRules.availability(deviceCount: found.count, authorized: Self.isAuthorized)
            guard state == .ready, let device = Self.device(for: resolved) else {
                Task { @MainActor in self?.publish(found, resolved, state, opened: nil, generation: token) }
                return
            }
            // Blocks while macOS opens the camera — the reason none of this is on the main thread.
            let opened = try? AVCaptureDeviceInput(device: device)
            Task { @MainActor in
                self?.publish(found, resolved, state, opened: opened, generation: token)
            }
        }
    }

    private func publish(_ found: [CameraMirrorDevice], _ resolved: String,
                         _ state: CameraMirrorRules.Availability,
                         opened: AVCaptureDeviceInput?, generation token: Int) {
        guard token == generation else { return }
        devices = found
        selection = resolved
        guard let opened else {
            availability = state == .ready ? .noCameras : state
            isStarting = false
            isMirrored = false
            return
        }
        session.beginConfiguration()
        if let input { session.removeInput(input) }
        guard session.canAddInput(opened) else {
            // The camera is there but would not open — in use by another app, or the grant went away.
            session.commitConfiguration()
            input = nil
            availability = .noCameras
            isStarting = false
            isMirrored = true
            return
        }
        session.addInput(opened)
        input = opened
        session.sessionPreset = .high
        session.commitConfiguration()
        availability = .ready
        guard !isRunning else {
            // A running session is live again as soon as the new input is in.
            isStarting = false
            return
        }
        isRunning = true
        let session = self.session
        // `startRunning` blocks until the camera is warm; it stays on the camera lane for the same reason.
        // The warm-up pane stays up until it returns, because only then can a frame arrive.
        queue.async { [weak self] in
            session.startRunning()
            Task { @MainActor in
                guard let self, self.wantsCamera else { return }
                self.isStarting = false
                self.isMirrored = true
            }
        }
    }

    // MARK: Camera lane

    nonisolated private static func discover() -> [CameraMirrorDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { CameraMirrorDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// "Not asked yet" counts as available only while a feature may still raise the prompt. Once the
    /// first-run pass is done, an undecided camera is *not* available: reporting it as ready left the
    /// page on a preview that never fills, instead of the "Camera Access Is Off" pane with its
    /// System Settings door.
    nonisolated private static var isAuthorized: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined { return PermissionBootstrap.mayPromptFromFeature }
        return status == .authorized
    }

    nonisolated private static func device(for id: String) -> AVCaptureDevice? {
        guard !id.isEmpty else { return AVCaptureDevice.default(for: .video) }
        return AVCaptureDevice(uniqueID: id) ?? AVCaptureDevice.default(for: .video)
    }
}
