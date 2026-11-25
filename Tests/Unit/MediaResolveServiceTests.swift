import XCTest
@testable import KatiKati

/// SD-5: the service's decisions and the pane's four visible outcomes, tested through the pure state the
/// service publishes — no `Process`, no `URLSession`, no AppKit. The effect-only branches (actually running a
/// yt-dlp, actually posting) are the owner's tool and are not faked here.
final class MediaResolveServiceTests: XCTestCase {
    func testNoToolMeansNothingIsAttempted() {
        XCTAssertEqual(MediaResolveState.route(tool: nil), .notConfigured)
        XCTAssertEqual(MediaResolveState.route(tool: "   "), .notConfigured)

        var state = MediaResolveState()
        state.begin()
        state.finish(.failure(.notConfigured))
        XCTAssertEqual(state.lastFailure, "Set a yt-dlp path or a resolver endpoint first.",
                       "the pane's needs-a-tool line")
        XCTAssertNil(state.lastFile)
        XCTAssertFalse(state.isResolving)
    }

    func testEndpointAndBinaryAreChosenByShape() {
        XCTAssertEqual(MediaResolveState.route(tool: "https://resolver.example.com/jobs"),
                       .endpoint(URL(string: "https://resolver.example.com/jobs")!))
        XCTAssertEqual(MediaResolveState.route(tool: "  http://127.0.0.1:8080/run  "),
                       .endpoint(URL(string: "http://127.0.0.1:8080/run")!))
        // `NSHomeDirectory()` differs under the test host's sandbox, so only the expansion itself is asserted
        // here; `testTheTildeIsExpandedForABinary` checks the result's shape.
        guard case .binary(let tildePath) = MediaResolveState.route(tool: "~/bin/yt-dlp") else {
            return XCTFail("a path is a binary route")
        }
        XCTAssertFalse(tildePath.hasPrefix("~"))
        XCTAssertEqual(MediaResolveState.route(tool: "/opt/homebrew/bin/yt-dlp"),
                       .binary("/opt/homebrew/bin/yt-dlp"))
        XCTAssertEqual(MediaResolveState.route(tool: "https://"), .notConfigured,
                       "a malformed endpoint is never run as a binary")
        XCTAssertEqual(MediaResolveState.route(tool: "http://no-host-here/"), .endpoint(URL(string: "http://no-host-here/")!))
    }

    func testTheTildeIsExpandedForABinary() {
        let route = MediaResolveState.route(tool: "~/bin/yt-dlp")
        guard case .binary(let path) = route else { return XCTFail("expected a binary route, got \(route)") }
        XCTAssertFalse(path.hasPrefix("~"))
        XCTAssertTrue(path.hasSuffix("/bin/yt-dlp"))
    }

    func testABinaryThatNamedItsFileIsTheSuccessOutcome() {
        let output = "[youtube] abc: Downloading\n[download] Destination: /tmp/clip.webm\n"
            + "Merging formats into \"/tmp/clip.mp4\"\n"
        XCTAssertEqual(MediaResolveState.binaryOutcome(terminationStatus: 0, output: output),
                       .success(URL(fileURLWithPath: "/tmp/clip.mp4")))
    }

    func testABinaryThatFailedCarriesItsLastLine() {
        let output = "[youtube] abc: Downloading\nERROR: Video unavailable\n"
        XCTAssertEqual(MediaResolveState.binaryOutcome(terminationStatus: 1, output: output),
                       .failure(.binaryFailed("ERROR: Video unavailable")))
    }

    func testACleanExitWithoutANameIsStillAFailure() {
        XCTAssertEqual(MediaResolveState.binaryOutcome(terminationStatus: 0, output: "nothing to see\n"),
                       .failure(.noFileProduced), "silence must not read as success")
    }

    func testEndpointAnswersMapStatusAndPath() {
        let ok = Data(#"{"path":"/tmp/from-endpoint.mp4"}"#.utf8)
        XCTAssertEqual(MediaResolveState.endpointOutcome(status: 201, data: ok),
                       .success(URL(fileURLWithPath: "/tmp/from-endpoint.mp4")))
        XCTAssertEqual(MediaResolveState.endpointOutcome(status: 503, data: ok),
                       .failure(.endpointFailed(503)))
        XCTAssertEqual(MediaResolveState.endpointOutcome(status: 200, data: Data(#"{"ok":true}"#.utf8)),
                       .failure(.noFileProduced))
        XCTAssertEqual(MediaResolveState.endpointOutcome(status: 200, data: Data("not json".utf8)),
                       .failure(.noFileProduced))
        XCTAssertEqual(MediaResolveState.endpointOutcome(status: 200, data: nil),
                       .failure(.noFileProduced))
        XCTAssertEqual(MediaResolveState.endpointOutcome(status: 200, data: Data(#"{"path":""}"#.utf8)),
                       .failure(.noFileProduced))
    }

    func testTheFunnelLeavesExactlyOneVisibleOutcome() {
        var state = MediaResolveState()
        state.finish(.success(URL(fileURLWithPath: "/tmp/old.mp4")))
        XCTAssertEqual(state.lastFile, URL(fileURLWithPath: "/tmp/old.mp4"))

        state.begin()
        XCTAssertTrue(state.isResolving)
        XCTAssertNil(state.lastFile, "a new resolve clears the previous result")
        XCTAssertNil(state.lastFailure)

        state.finish(.success(URL(fileURLWithPath: "/tmp/new.mp4")))
        XCTAssertFalse(state.isResolving)
        XCTAssertEqual(state.lastFile, URL(fileURLWithPath: "/tmp/new.mp4"))
        XCTAssertNil(state.lastFailure, "success and failure are never both shown")

        state.finish(.failure(.endpointFailed(500)))
        XCTAssertFalse(state.isResolving)
        XCTAssertNil(state.lastFile)
        XCTAssertEqual(state.lastFailure, "The resolver endpoint answered 500.")
    }
}
