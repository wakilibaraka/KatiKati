import CoreGraphics

/// Named pure seam for snap-zone rectangle computation (Phase 26a).
/// Delegates to `SnapPosition.frame(in:)` so the logic has a single home;
/// this type is the stable surface the golden tests and the hotkey dispatcher pin against.
enum SnapRects {
    /// Returns the target Cocoa frame (bottom-left origin, whole points) for `position`
    /// inside the given `visibleFrame`. The result is identical to `position.frame(in:)`.
    static func rect(for position: SnapPosition, in visibleFrame: CGRect) -> CGRect {
        position.frame(in: visibleFrame)
    }
}
