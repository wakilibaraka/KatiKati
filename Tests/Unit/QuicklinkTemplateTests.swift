import XCTest
@testable import KatiKati

final class QuicklinkTemplateTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testQueryIsPercentEncodedInURLs() {
        let v = QuicklinkValues(query: "a b&c=d/é")
        XCTAssertEqual(QuicklinkTemplate.expand("https://x.test/s?q={query}", values: v, calendar: utc),
                       "https://x.test/s?q=a%20b%26c%3Dd%2F%C3%A9")
    }

    func testNonURLTemplatesInsertVerbatim() {
        let v = QuicklinkValues(query: "a b")
        XCTAssertEqual(QuicklinkTemplate.expand("/Users/me/{query}", values: v, calendar: utc), "/Users/me/a b")
    }

    func testAllTokensAndDate() {
        let v = QuicklinkValues(query: "q", clipboard: "c c", selection: "s", date: Date(timeIntervalSince1970: 86_400 * 365))
        XCTAssertEqual(QuicklinkTemplate.expand("https://x.test/{query}/{clipboard}/{selection}/{date}", values: v, calendar: utc),
                       "https://x.test/q/c%20c/s/1971-01-01")
    }

    func testUnknownTokensAreLeftAlone() {
        XCTAssertEqual(QuicklinkTemplate.expand("https://x.test/{nope}", values: QuicklinkValues(), calendar: utc), "https://x.test/{nope}")
    }

    func testPlaceholderDetection() {
        XCTAssertTrue(QuicklinkTemplate.hasPlaceholder("a{date}"))
        XCTAssertFalse(QuicklinkTemplate.hasPlaceholder("https://x.test"))
        XCTAssertTrue(QuicklinkTemplate.needsQuery("a{query}"))
        XCTAssertFalse(QuicklinkTemplate.needsQuery("a{date}"))
    }

    func testURLBuilder() {
        XCTAssertEqual(QuicklinkTemplate.url("https://x.test/?q={query}", values: QuicklinkValues(query: "hi there"), calendar: utc)?.absoluteString,
                       "https://x.test/?q=hi%20there")
    }

    func testCodableRoundTrip() throws {
        let link = Quicklink(name: "GH", template: "https://github.com/search?q={query}", openWith: "com.apple.Safari")
        XCTAssertEqual(try JSONDecoder().decode(Quicklink.self, from: JSONEncoder().encode(link)), link)
    }
}
