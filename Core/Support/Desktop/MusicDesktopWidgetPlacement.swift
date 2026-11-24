import AppKit

// MARK: - §10 desktop music widget: live placement

/// One panel's live move/resize channels, handed to the SwiftUI card. Bound weakly, so the view never keeps
/// its own window alive.
@MainActor
struct MusicDesktopWidgetInteraction {
    let move: @MainActor (CGSize) -> Void
    let resize: @MainActor (CGSize) -> Void
    let commit: @MainActor () -> Void
}

/// Where each display's music widget was left. One `UserDefaults` blob, exactly as before; the defaults and
/// key are parameters so a test can own its own suite instead of the app's real record.
struct MusicDesktopWidgetFrameStore {
    var defaults: UserDefaults = .standard
    var key: String = MusicSurfaceConfig.desktopFramesKey

    func frames() -> [String: NormalizedWidgetRect] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: NormalizedWidgetRect].self, from: data) else { return [:] }
        return decoded
    }

    /// The restored frame for a display, clamped by the same geometry the live panel uses.
    func rect(for displayID: String, in bounds: CGRect) -> CGRect? {
        frames()[displayID].map { MusicDesktopWidgetGeometry.frame(from: $0, in: bounds) }
    }

    /// Stores the frame the widget actually ended on, normalized to the surface it sits in.
    func record(_ rect: CGRect, for displayID: String, in bounds: CGRect) {
        var all = frames()
        let next = MusicDesktopWidgetGeometry.normalized(rect, in: bounds)
        if let existing = all[displayID], Self.rectsApproximatelyEqual(existing, next) { return }
        all[displayID] = next
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }

    private static func rectsApproximatelyEqual(_ lhs: NormalizedWidgetRect, _ rhs: NormalizedWidgetRect) -> Bool {
        abs(lhs.x - rhs.x) < 1e-4 &&
        abs(lhs.y - rhs.y) < 1e-4 &&
        abs(lhs.width - rhs.width) < 1e-4 &&
        abs(lhs.height - rhs.height) < 1e-4
    }
}

/// One panel's live placement: it reads the real window's frame, applies the clamped/anchored geometry and
/// commits the result to the per-display record. The controller drives it in production, and it can be driven
/// with a real `NSPanel` and a synthetic surface, so a no-op move or a wrong anchor shows up in a test.
@MainActor
final class MusicDesktopWidgetPlacement {
    private(set) weak var panel: NSPanel?
    let displayID: String
    private(set) var preset: MusicDesktopWidgetPreset
    /// The surface the panel is held inside; refreshed on every reload, since screens and the Dock move.
    private(set) var bounds: CGRect
    private var store: MusicDesktopWidgetFrameStore
    private var isApplyingFrame = false

    init(panel: NSPanel,
         displayID: String,
         preset: MusicDesktopWidgetPreset,
         bounds: CGRect,
         store: MusicDesktopWidgetFrameStore = MusicDesktopWidgetFrameStore()) {
        self.panel = panel
        self.displayID = displayID
        self.preset = preset
        self.bounds = bounds
        self.store = store
    }

    func update(preset: MusicDesktopWidgetPreset, bounds: CGRect) {
        self.preset = preset
        self.bounds = bounds
    }

    /// The frame remembered for this display, if any: what a reload restores in place of the preset rect.
    var restoredFrame: CGRect? { store.rect(for: displayID, in: bounds) }

    /// The exact channels the SwiftUI card holds in production.
    var interaction: MusicDesktopWidgetInteraction {
        MusicDesktopWidgetInteraction(
            move: { [weak self] delta in self?.move(by: delta) },
            resize: { [weak self] delta in self?.resize(by: delta) },
            commit: { [weak self] in self?.commit() }
        )
    }

    /// A live drag: the panel follows the pointer, held inside the surface.
    func move(by delta: CGSize) {
        guard let panel, !isApplyingFrame else { return }
        let rect = MusicDesktopWidgetGeometry.moved(panel.frame, by: delta, into: bounds)
        applyFrame(rect, display: true)
    }

    /// A live resize: the top-leading corner holds still and the panel never shrinks below the preset minimum
    /// (a strip keeps its height). Poster is a picture and never resizes.
    func resize(by delta: CGSize) {
        guard let panel, !isApplyingFrame, preset != .poster else { return }
        let rect = MusicDesktopWidgetGeometry.resized(panel.frame, by: delta, preset: preset, into: bounds)
        applyFrame(rect, display: true)
    }

    /// Snap, apply, remember: the frame the widget ends on is the frame that comes back next launch.
    @discardableResult
    func commit() -> CGRect? {
        guard let panel, !isApplyingFrame else { return nil }
        let rect = MusicDesktopWidgetGeometry.snap(panel.frame, into: bounds)
        applyFrame(rect, display: true)
        store.record(rect, for: displayID, in: bounds)
        return rect
    }

    func applyFrame(_ rect: CGRect, display: Bool = true) {
        guard let panel, !isApplyingFrame, !Self.framesEqual(panel.frame, rect) else { return }
        isApplyingFrame = true
        defer { isApplyingFrame = false }
        panel.setFrame(rect, display: display)
    }

    private static func framesEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5 &&
        abs(lhs.minY - rhs.minY) < 0.5 &&
        abs(lhs.width - rhs.width) < 0.5 &&
        abs(lhs.height - rhs.height) < 0.5
    }
}
