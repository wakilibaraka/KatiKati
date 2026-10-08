import XCTest
@testable import KatiKati

final class SystemStatusProviderTests: XCTestCase {
    func testProviderDefaults() {
        let provider = SystemStatusProvider()
        XCTAssertEqual(provider.batteryLevel, 100)
        XCTAssertFalse(provider.isCharging)
        XCTAssertTrue(provider.isWiFiConnected)
    }
}
