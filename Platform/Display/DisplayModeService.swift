import AppKit
import CoreGraphics

/// SN-6: the CoreGraphics half of display modes.
///
/// Two details decide whether this works on an external panel at all: the query must pass
/// `kCGDisplayShowDuplicateLowResolutionModes`, because otherwise CG hides the scaled HiDPI modes and a
/// 4K looks like it only offers 3840×2160 and 1920×1080 with nothing in between; and every apply is
/// provisional for fifteen seconds, because a mode the panel cannot display is a black screen with no
/// way back from inside the app.
@MainActor
enum DisplayModeService {
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Every mode the panel advertises, including the duplicate low-resolution variants that carry the
    /// HiDPI backing stores.
    static func modes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let flags = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return CGDisplayCopyAllDisplayModes(displayID, flags) as? [CGDisplayMode] ?? []
    }

    static func currentMode(for displayID: CGDirectDisplayID) -> CGDisplayMode? {
        CGDisplayCopyDisplayMode(displayID)
    }

    static func option(for mode: CGDisplayMode) -> DisplayModeOption {
        // `width`/`height` are points for a scaled mode and `pixelWidth`/`pixelHeight` the backing store,
        // which is exactly the ratio the catalog classifies.
        DisplayModeOption(
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            pointWidth: mode.width,
            pointHeight: mode.height,
            refresh: mode.refreshRate
        )
    }

    /// The CG mode behind an option id, so a menu can hold plain values and apply them later.
    static func mode(matching option: DisplayModeOption, for displayID: CGDirectDisplayID) -> CGDisplayMode? {
        modes(for: displayID).first { candidate in
            let candidateOption = self.option(for: candidate)
            return candidateOption.id == option.id
        }
    }

    /// Applies `mode`. Returns the mode that was in effect, which is what a revert needs.
    @discardableResult
    static func apply(_ mode: CGDisplayMode, to displayID: CGDirectDisplayID) -> CGDisplayMode? {
        let previous = currentMode(for: displayID)
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return nil }
        CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
        guard CGCompleteDisplayConfiguration(config, .permanently) == .success else { return nil }
        return previous
    }

    /// Puts a display back the way it was; used by the timer and by the alert's Revert button.
    @discardableResult
    static func restore(_ mode: CGDisplayMode, to displayID: CGDirectDisplayID) -> Bool {
        apply(mode, to: displayID) != nil
    }
}

extension DisplayModeService {
    /// Captures where every connected display sits right now, keyed by display UUID.
    @MainActor
    static func captureArrangement(named name: String) -> DisplayArrangement? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        let entries = screens.compactMap { screen -> DisplayArrangementEntry? in
            guard let key = DisplayIdentity.uuidString(for: screen) else { return nil }
            return DisplayArrangementGeometry.entry(displayKey: key,
                                                    cocoaFrame: screen.frame,
                                                    primaryMaxY: primary.frame.maxY)
        }
        guard !entries.isEmpty else { return nil }
        return DisplayArrangement(name: name, entries: DisplayArrangementGeometry.normalized(entries))
    }

    /// Puts every display back where the preset says. Refuses a preset that names a display which is no
    /// longer connected, so a partial match cannot shuffle the panels that are.
    @MainActor
    @discardableResult
    static func applyArrangement(_ arrangement: DisplayArrangement) -> Bool {
        let screens = NSScreen.screens
        let keyed = Dictionary(uniqueKeysWithValues: screens.compactMap { screen in
            DisplayIdentity.uuidString(for: screen).map { ($0, screen) }
        })
        guard DisplayArrangementGeometry.isComplete(arrangement, liveKeys: Set(keyed.keys)) else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for entry in arrangement.entries {
            guard let screen = keyed[entry.displayKey], let displayID = displayID(for: screen) else { continue }
            CGConfigureDisplayOrigin(config, displayID,
                                     Int32(entry.originX.rounded()), Int32(entry.originY.rounded()))
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}

/// Asks the user to keep a mode and reverts automatically if they do not answer within `seconds`.
/// The prompt is deliberately modal: while it is up the screen may be unusable, and one keystroke has to
/// be enough to get the old mode back.
@MainActor
final class DisplayModeSwitcher {
    static let shared = DisplayModeSwitcher()

    private var pendingRevert: Timer?

    private init() {}

    /// Applies `option` and prompts. A `.needsAccessibility`-style failure returns false and changes nothing.
    @discardableResult
    func apply(_ option: DisplayModeOption, on screen: NSScreen, seconds: TimeInterval = 15) -> Bool {
        guard let displayID = DisplayModeService.displayID(for: screen),
              let target = DisplayModeService.mode(matching: option, for: displayID) else { return false }
        // Applying the mode that is already on would still re-run the configuration cycle; skip it.
        if let current = DisplayModeService.currentMode(for: displayID),
           DisplayModeCatalog.isSamePicture(DisplayModeService.option(for: current), option) {
            return true
        }
        guard let previous = DisplayModeService.apply(target, to: displayID) else { return false }
        prompt(previous: previous, displayID: displayID, seconds: seconds)
        return true
    }

    private func prompt(previous: CGDisplayMode, displayID: CGDirectDisplayID, seconds: TimeInterval) {
        pendingRevert?.invalidate()

        let alert = NSAlert()
        alert.messageText = String(localized: "Keep this display mode?")
        alert.informativeText = String(localized: "The previous mode comes back automatically if you do not answer.")
        alert.addButton(withTitle: String(localized: "Keep"))
        alert.addButton(withTitle: String(localized: "Revert"))
        alert.alertStyle = .warning

        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated {
                DisplayModeService.restore(previous, to: displayID)
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingRevert = timer

        let response = alert.runModal()
        timer.invalidate()
        pendingRevert = nil
        if response == .alertSecondButtonReturn {
            DisplayModeService.restore(previous, to: displayID)
        }
    }
}
