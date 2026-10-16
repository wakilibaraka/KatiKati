import Foundation

// Phase 47b — the pure half of the notch's camera mirror: which camera the page opens, and what it has
// to say when there is none to open. The `AVCaptureSession` itself lives in the app layer
// (`CameraMirrorService`), so the decisions stay here and stay unit-tested like every other rule in Core.
// Dual-compiled into the app + test targets, exactly like `NotchFallbackPlan.swift`.

/// One camera as the page's dropdown and its stored choice see it.
struct CameraMirrorDevice: Equatable, Sendable {
    /// `AVCaptureDevice.uniqueID`. Empty means "whatever macOS calls the default camera".
    let id: String
    let name: String
}

enum CameraMirrorRules {
    /// Which camera id to open: the stored one while that camera is still attached, the system default
    /// otherwise. A camera that was unplugged must not leave the page opening nothing at all.
    static func resolvedSelection(stored: String, available: [CameraMirrorDevice]) -> String {
        guard !stored.isEmpty else { return "" }
        return available.contains { $0.id == stored } ? stored : ""
    }

    /// What the page shows instead of a preview.
    enum Availability: Equatable, Sendable {
        case ready          // a camera and the grant: show the mirror
        case noCameras      // nothing attached, or the device could not be opened
        case denied         // the camera grant is refused or restricted
    }

    /// `authorized` counts "not asked yet" as yes: the page is what raises the prompt.
    static func availability(deviceCount: Int, authorized: Bool) -> Availability {
        if !authorized { return .denied }
        return deviceCount > 0 ? .ready : .noCameras
    }

    /// System Settings › Privacy & Security › Camera, where a refusal is undone.
    static let cameraSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
}
