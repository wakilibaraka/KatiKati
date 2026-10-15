import AppKit
import SwiftUI

/// The ▲▼ "cursor" drawn while the pointer is over a taskbar grip zone or dragging the bar's
/// height. It is a real view in its own tiny panel, not an `NSCursor`: a background app cannot
/// change the system cursor, but it can hide it (`SystemCursorHider`) and draw its own glyph
/// under the pointer. Use the system frame-resize artwork, including its padding and hotspot.
@MainActor
struct ResizeCursorGlyph: View {
    private static let cursor: NSCursor = .frameResize(position: .top, directions: .all)

    static var size: CGSize { cursor.image.size }
    static var hotSpot: CGPoint { cursor.hotSpot }
    static var image: NSImage { cursor.image }

    var body: some View {
        Image(nsImage: Self.image)
            .frame(width: Self.size.width, height: Self.size.height)
    }
}
