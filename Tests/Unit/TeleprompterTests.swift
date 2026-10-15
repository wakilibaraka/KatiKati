import XCTest
@testable import KatiKati

// Phase 37a — teleprompter pure rules.
final class TeleprompterTests: XCTestCase {
    func testSpeedScalesWithWPMAndFont() {
        let slow = TeleprompterSpeed.pointsPerSecond(wpm: 100, fontSize: 30)
        XCTAssertGreaterThan(TeleprompterSpeed.pointsPerSecond(wpm: 200, fontSize: 30), slow)
        XCTAssertGreaterThan(TeleprompterSpeed.pointsPerSecond(wpm: 100, fontSize: 40), slow)
    }

    func testScrollStopsAtEndAndIgnoresStalledFrames() {
        var s = TeleprompterScroll()
        XCTAssertTrue(s.advance(dt: 0.5, wpm: 140, fontSize: 30, contentHeight: 1000))
        let before = s.offset
        XCTAssertTrue(s.advance(dt: 5, wpm: 140, fontSize: 30, contentHeight: 1000))   // stalled frame: no jump
        XCTAssertEqual(s.offset, before)
        XCTAssertFalse(s.advance(dt: 0.9, wpm: 260, fontSize: 64, contentHeight: before + 1))
        XCTAssertEqual(s.offset, before + 1)
        s.nudge(-99999, contentHeight: 1000); XCTAssertEqual(s.offset, 0)
    }

    func testLinksAreFoundOnceAndOnlyHTTP() {
        let urls = ScriptLinks.urls(in: "Read https://example.com/a and https://example.com/a, also mailto:me@x.com and http://b.org/x")
        XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com/a", "http://b.org/x"])
    }

    func testFetchPolicyIsHTTPSAndPublicOnly() {
        XCTAssertEqual(LinkFetchPolicy.verdict(for: URL(string: "https://example.com/p")!), .allowed)
        XCTAssertEqual(LinkFetchPolicy.verdict(for: URL(string: "http://example.com")!), .insecure)
        for host in ["https://localhost/x", "https://127.0.0.1/", "https://192.168.1.5/", "https://10.0.0.2/", "https://172.20.1.1/", "https://printer.local/", "https://[::1]/"] {
            XCTAssertEqual(LinkFetchPolicy.verdict(for: URL(string: host)!), .privateHost, host)
        }
    }

    func testExtractKeepsArticleTextAndDropsChrome() {
        let body = String(repeating: "Real sentence &amp; more. ", count: 20)
        let html = "<html><head><title>My &quot;Title&quot;</title><style>p{}</style></head><body><nav>MENU</nav><script>var x=1</script><article><h1>Head</h1><p>\(body)</p><p>Second&nbsp;para &#8217;s &#x41;</p></article><footer>FOOT</footer></body></html>"
        let r = ReadableText.extract(html: html)
        XCTAssertEqual(r.title, "My \"Title\"")
        XCTAssertTrue(r.text.contains("Real sentence & more."))
        XCTAssertTrue(r.text.contains("Second para ’s A"))
        for junk in ["MENU", "FOOT", "var x", "<p>"] { XCTAssertFalse(r.text.contains(junk), junk) }
    }

    func testHostileOrEmptyHTMLYieldsShortText() {
        XCTAssertLessThan(ReadableText.extract(html: "<html><body><script>document.write('x')</script></body></html>").text.count, ReadableText.minimumUsefulLength)
        XCTAssertEqual(ReadableText.extract(html: "").text, "")
    }
}
