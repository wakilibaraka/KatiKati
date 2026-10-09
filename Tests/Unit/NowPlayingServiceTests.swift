import XCTest
@testable import KatiKati

final class NowPlayingServiceTests: XCTestCase {
    
    // MARK: - 4f3: Now Playing Service
    
    /// Verify that the service initializes, loads the private framework safely,
    /// and provides an initial state.
    func testServiceInitializationAndState() {
        let service = NowPlayingService()
        XCTAssertNotNil(service)
        
        // At launch, it's very likely nothing is playing in the test environment,
        // but we just want to ensure it doesn't crash and the state is available.
        XCTAssertFalse(service.state.isPlaying)
        XCTAssertNil(service.state.title)
        XCTAssertNil(service.state.artist)
    }
    
    /// Ensure togglePlayPause does not crash.
    func testTogglePlayPause() {
        let service = NowPlayingService()
        service.togglePlayPause()
        // No assertions possible without mocking MediaRemote, but this confirms
        // the function is callable.
    }
}
