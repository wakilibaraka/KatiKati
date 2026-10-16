import XCTest
@testable import KatiKati

// Phase 47b — the camera mirror's pure rules, and the notch page it adds to the gallery.

final class CameraMirrorTests: XCTestCase {
    private let builtIn = CameraMirrorDevice(id: "BuiltIn-1", name: "FaceTime HD Camera")
    private let phone = CameraMirrorDevice(id: "iPhone-1", name: "Emmanuel's iPhone Camera")

    /// The stored camera is opened while it is attached; an unplugged one falls back to the system
    /// default instead of leaving the page opening nothing.
    func testSelectionKeepsAnAttachedCameraAndFallsBackWhenItIsGone() {
        XCTAssertEqual(CameraMirrorRules.resolvedSelection(stored: "iPhone-1", available: [builtIn, phone]), "iPhone-1")
        XCTAssertEqual(CameraMirrorRules.resolvedSelection(stored: "USB-9", available: [builtIn, phone]), "")
        XCTAssertEqual(CameraMirrorRules.resolvedSelection(stored: "USB-9", available: []), "")
        XCTAssertEqual(CameraMirrorRules.resolvedSelection(stored: "", available: [builtIn]), "")
    }

    /// A refused grant is its own answer — never "no camera", which would send the owner looking for a
    /// camera that is plugged in.
    func testAvailabilitySeparatesARefusalFromHavingNoCamera() {
        XCTAssertEqual(CameraMirrorRules.availability(deviceCount: 2, authorized: true), .ready)
        XCTAssertEqual(CameraMirrorRules.availability(deviceCount: 1, authorized: false), .denied)
        XCTAssertEqual(CameraMirrorRules.availability(deviceCount: 0, authorized: true), .noCameras)
        XCTAssertEqual(CameraMirrorRules.availability(deviceCount: 0, authorized: false), .denied)
    }

    /// The refusal's door lands on the camera list, not on the Automation list the players use.
    func testTheRefusalDoorOpensTheCameraPane() {
        XCTAssertEqual(CameraMirrorRules.cameraSettingsURL?.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    /// The mirror page exists only while its switch is on, and it takes its place after the teleprompter.
    func testTheMirrorPageJoinsTheGalleryOnlyWhenItIsSwitchedOn() {
        XCTAssertEqual(NotchPage.visible(teleprompter: false).count, 6)
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: true).last, .cameraMirror)
        XCTAssertEqual(NotchPage.visible(teleprompter: true, mirror: true).count, 8)
        XCTAssertFalse(NotchPage.visible(teleprompter: true).contains(.cameraMirror))

        // Paging follows the same gallery: from the last always-on page, forward lands on the mirror.
        XCTAssertEqual(NotchPage.hardwareHud.next(teleprompter: false, mirror: true), .cameraMirror)
        XCTAssertEqual(NotchPage.cameraMirror.next(teleprompter: false, mirror: true), .aiTracker)
        XCTAssertEqual(NotchPage.cameraMirror.previous(teleprompter: false, mirror: true), .hardwareHud)
        XCTAssertEqual(NotchPage.cameraMirror.next(teleprompter: false), .aiTracker)
    }
}
