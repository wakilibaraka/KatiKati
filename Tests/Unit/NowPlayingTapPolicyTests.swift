import XCTest
@testable import KatiKati

final class NowPlayingTapPolicyTests: XCTestCase {
    func testPresetsMapSingleAndDoubleClick() {
        let table: [(NowPlayingTapPreset, NowPlayingTapAction, NowPlayingTapAction)] = [
            (.playPauseThenPlayer, .playPause, .openPlayer),
            (.playerThenPlayPause, .openPlayer, .playPause),
            (.sourceAppThenPlayPause, .openSourceApp, .playPause),
        ]
        for (preset, single, double) in table {
            XCTAssertEqual(preset.action(forTaps: 1), single)
            XCTAssertEqual(preset.action(forTaps: 2), double)
        }
    }

    func testDefaultIsPlayPauseThenSourceApp() {
        XCTAssertEqual(NowPlayingTapPreset.default, .playPauseThenSourceApp)
    }
}
