import XCTest
@testable import KatiKati

final class NowPlayingServiceTests: XCTestCase {
    func testNowPlayingServiceInitialization() {
        let service = NowPlayingService()
        XCTAssertNotNil(service)
        XCTAssertNil(service.title)
        XCTAssertNil(service.artist)
        XCTAssertFalse(service.isPlaying)
    }
}
