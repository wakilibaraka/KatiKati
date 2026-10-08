import XCTest
@testable import KatiKati

final class ClockChipContentTests: XCTestCase {
    
    func testStandardClockProvider() {
        let provider = StandardClockProvider()
        
        let testDate = Date(timeIntervalSince1970: 1687000000) // roughly June 2023
        
        let content = provider.currentContent(for: testDate)
        
        XCTAssertFalse(content.primaryText.isEmpty, "Time string should not be empty")
        XCTAssertNotNil(content.secondaryText)
        XCTAssertFalse(content.secondaryText!.isEmpty, "Date string should not be empty")
    }
}
