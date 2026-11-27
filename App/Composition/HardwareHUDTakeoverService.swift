import AppKit
import Combine
import Foundation
import os.lock

/// N3–N5: replaces the macOS system volume/brightness/keyboard OSD with KatiKati's hardware HUD.
/// Off by default (`com.katikati.notch.hudTakeover`); kills cleanly via `DOCK_HUD_TAKEOVER=0`, and
/// passes through any key whose target hardware cannot be controlled (e.g. fixed-volume HDMI audio).
@MainActor
final class HardwareHUDTakeoverService {
    static let shared = HardwareHUDTakeoverService()

    static let enabledKey = "com.katikati.notch.hudTakeover"
    static let volumeKeyHUDNotification = Notification.Name("com.katikati.hardwareVolumeKeyHUD")

    private let tap = MediaKeyTap()
    private let statusService = SystemStatusService()
    private var holdsStatus = false
    private var defaultsObserver: NSObjectProtocol?
    private var statusCancellable: AnyCancellable?
    private let availability = HardwareControlAvailabilityBox()

    private init() {
        tap.setAvailability { [availability] kind in
            availability.allows(kind)
        }
        tap.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    func startObserving() {
        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        let on = Self.isEnabled && DebugSwitch.hudTakeover.isEnabled()
        if on {
            if !holdsStatus {
                statusService.acquire()
                holdsStatus = true
                statusCancellable = statusService.$status
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.syncAvailability() }
            }
            syncAvailability()
            tap.setEnabled(true)
        } else {
            tearDownTap()
        }
    }

    func tearDown() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        tearDownTap()
    }

    private func tearDownTap() {
        tap.tearDown()
        statusCancellable?.cancel()
        statusCancellable = nil
        if holdsStatus {
            statusService.release()
            holdsStatus = false
        }
    }

    private func syncAvailability() {
        availability.update(
            canControlVolume: SystemStatusService.canControlDefaultOutputVolume(),
            canControlBrightness: DisplayBrightness.shared.canControlCursorScreen(),
            canControlKeyboard: KeyboardBacklight.isAvailable
        )
    }

    private func handle(_ event: MediaKeyEvent) {
        switch event.key {
        case .volumeUp, .volumeDown:
            let increasing = event.key == .volumeUp
            let current = statusService.currentVolumeLevel
            let next = MediaKeyDecode.steppedLevel(current: current, increasing: increasing, fine: event.isFineStep)
            if increasing && statusService.status.volume.isMuted && next > 0 {
                _ = SystemStatusService.setDefaultOutputMuted(false)
            }
            _ = statusService.setVolume(Float(next))
            let muted = (!increasing && next <= 0.001) || (statusService.status.volume.isMuted && !increasing)
            NotificationCenter.default.post(
                name: Self.volumeKeyHUDNotification,
                object: nil,
                userInfo: ["level": muted ? 0.0 : next, "muted": muted]
            )

        case .mute:
            let wasMuted = SystemStatusService.isDefaultOutputMuted() ?? statusService.status.volume.isMuted
            _ = statusService.toggleMute()
            let nowMuted = !wasMuted
            let level = nowMuted ? 0.0 : statusService.currentVolumeLevel
            NotificationCenter.default.post(
                name: Self.volumeKeyHUDNotification,
                object: nil,
                userInfo: ["level": level, "muted": nowMuted]
            )

        case .brightnessUp, .brightnessDown:
            let screen = DisplayBrightness.targetScreen()
            let current = DisplayBrightness.shared.level(for: screen) ?? 0.5
            let next = MediaKeyDecode.steppedLevel(current: current, increasing: event.key == .brightnessUp, fine: event.isFineStep)
            DisplayBrightness.shared.set(next, for: screen)

        case .illuminationUp, .illuminationDown:
            let current = KeyboardBacklight.current() ?? 0.5
            let next = MediaKeyDecode.steppedLevel(current: current, increasing: event.key == .illuminationUp, fine: event.isFineStep)
            KeyboardBacklight.set(next)
        }
    }
}

private final class HardwareControlAvailabilityBox: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var canControlVolume = false
    private var canControlBrightness = false
    private var canControlKeyboard = false

    func update(canControlVolume: Bool, canControlBrightness: Bool, canControlKeyboard: Bool) {
        os_unfair_lock_lock(&lock)
        self.canControlVolume = canControlVolume
        self.canControlBrightness = canControlBrightness
        self.canControlKeyboard = canControlKeyboard
        os_unfair_lock_unlock(&lock)
    }

    func allows(_ kind: MediaKeyKind) -> Bool {
        os_unfair_lock_lock(&lock)
        let vol = canControlVolume
        let bri = canControlBrightness
        let kbd = canControlKeyboard
        os_unfair_lock_unlock(&lock)
        switch kind {
        case .volumeUp, .volumeDown, .mute: return vol
        case .brightnessUp, .brightnessDown: return bri
        case .illuminationUp, .illuminationDown: return kbd
        }
    }
}
