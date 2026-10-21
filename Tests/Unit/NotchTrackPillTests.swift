import SwiftUI
import XCTest
@testable import KatiKati

/// The track pill sizes itself to its text. Owner screenshot 2026-10-21: the text column had collapsed
/// and both lines rendered as slivers, because `MarqueeText` takes the width it is offered and the pill
/// only offered a `maxWidth`.
@MainActor
final class NotchTrackPillTests: XCTestCase {
    func testColumnWidthNeverCollapsesAndNeverExceedsTheCap() {
        XCTAssertEqual(TrackPillTextMetrics.columnWidth(title: "", artist: ""), TrackPillTextMetrics.floor,
                       "an empty pill still leaves the bars in from the edge")
        let medium = TrackPillTextMetrics.columnWidth(title: "A medium title", artist: "An artist")
        XCTAssertGreaterThan(medium, TrackPillTextMetrics.floor)
        XCTAssertLessThan(medium, TrackPillTextMetrics.cap)
        let long = TrackPillTextMetrics.columnWidth(title: String(repeating: "Long title ", count: 20), artist: "")
        XCTAssertEqual(long, TrackPillTextMetrics.cap, "a long title scrolls instead of stretching the pill")
    }

    func testALongTitleLaysThePillOutWideInsteadOfACollapsedColumn() {
        let pill = NotchTrackPillContent(
            title: String(repeating: "A long song title ", count: 6),
            artist: "Some Artist",
            artwork: nil,
            isPlaying: false
        )
        let size = NSHostingView(rootView: pill).fittingSize
        // 34 art + 10 + 170 text + 10 + 18 bars. The collapsed column measured the pill at 76 wide, with
        // the text as slivers (probe on the pre-fix layout, 2026-10-21).
        XCTAssertGreaterThan(size.width, 200)
        XCTAssertGreaterThanOrEqual(size.height, 34)
    }
}
