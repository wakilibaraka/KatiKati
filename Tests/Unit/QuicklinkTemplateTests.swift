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

    func testParseAndSerializeLineFormat() {
        let raw = """
        gh = https://github.com/search?q={query}
        daily = https://notes.test/{date}
        invalid line without equals
        """
        let parsed = Quicklink.parse(raw)
        XCTAssertEqual(parsed.map(\.name), ["gh", "daily"])
        XCTAssertEqual(parsed.map(\.template), ["https://github.com/search?q={query}", "https://notes.test/{date}"])
        XCTAssertEqual(Quicklink.serialize(parsed), "gh = https://github.com/search?q={query}\ndaily = https://notes.test/{date}")
    }

    func testMatchingExtractsQueryArgumentAndPrefixMatches() {
        let gh = Quicklink(name: "gh", template: "https://github.com/search?q={query}")
        let docs = Quicklink(name: "github-docs", template: "https://docs.github.com/{clipboard}")
        let links = [gh, docs]

        // Prefix match without argument
        let prefixMatches = QuicklinkTemplate.matching("g", in: links)
        XCTAssertEqual(prefixMatches.map(\.quicklink.name), ["gh", "github-docs"])
        XCTAssertEqual(prefixMatches.map(\.argument), ["", ""])

        // Exact keyword + space + query argument for a {query} template
        let argMatches = QuicklinkTemplate.matching("gh swift concurrency", in: links)
        XCTAssertEqual(argMatches, [Quicklink.Match(quicklink: gh, argument: "swift concurrency")])

        // Non-{query} template does not take trailing arguments
        XCTAssertTrue(QuicklinkTemplate.matching("github-docs extra", in: links).isEmpty)
    }
}
