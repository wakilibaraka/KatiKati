import XCTest
@testable import KatiKati

final class MediaResolverTests: XCTestCase {
    func testOnlyRealLinksAreAccepted() {
        XCTAssertTrue(MediaResolver.isSupported(URL(string: "https://example.com/watch?v=1")!))
        XCTAssertTrue(MediaResolver.isSupported(URL(string: "http://example.com/a.mp4")!))
        XCTAssertFalse(MediaResolver.isSupported(URL(string: "file:///tmp/a.mp4")!))
        XCTAssertFalse(MediaResolver.isSupported(URL(string: "ftp://example.com/a")!))
        XCTAssertFalse(MediaResolver.isSupported(URL(string: "https://")!))
        XCTAssertFalse(MediaResolver.isSupported(URL(string: "example.com")!))
    }

    func testQualitySelectorsAndLabels() {
        XCTAssertEqual(MediaQuality.allCases.map(\.label), ["Best", "1080p", "720p", "480p", "Audio"])
        XCTAssertEqual(MediaQuality.p720.formatSelector, "bestvideo[height<=720]+bestaudio/best[height<=720]")
        XCTAssertTrue(MediaQuality.audio.isAudioOnly)
        XCTAssertFalse(MediaQuality.p1080.isAudioOnly)
    }

    func testArgumentsCarryQualityMuteAndOutputDirectory() {
        let url = URL(string: "https://example.com/watch?v=abc")!
        let video = MediaResolver.arguments(for: url, options: MediaResolveOptions(quality: .p720, mute: true),
                                            outputDirectory: "/Users/tester/Downloads")
        XCTAssertEqual(Array(video.prefix(3)), ["--no-playlist", "-f", MediaQuality.p720.formatSelector])
        XCTAssertTrue(video.contains("--postprocessor-args"))
        XCTAssertTrue(video.contains("ffmpeg:-an"), "mute drops the audio track")
        XCTAssertTrue(video.contains("/Users/tester/Downloads/%(title).120s.%(ext)s"))
        XCTAssertEqual(video.last, url.absoluteString)

        let audio = MediaResolver.arguments(for: url, options: MediaResolveOptions(quality: .audio),
                                            outputDirectory: "/tmp")
        XCTAssertTrue(audio.contains("-x"))
        XCTAssertTrue(audio.contains("mp3"))
        XCTAssertFalse(audio.contains("--postprocessor-args"), "mute is meaningless for an audio-only download")
    }

    func testACustomNameReplacesTheTitleTemplate() {
        let url = URL(string: "https://example.com/v")!
        let args = MediaResolver.arguments(for: url,
                                           options: MediaResolveOptions(fileName: "My Clip: part 1/2"),
                                           outputDirectory: "/tmp")
        XCTAssertTrue(args.contains("/tmp/My Clip- part 1-2.%(ext)s"), "separators are replaced, the extension is kept")
    }

    func testSanitiseRejectsWhatCannotBeAName() {
        XCTAssertNil(MediaResolver.sanitise(""))
        XCTAssertNil(MediaResolver.sanitise("   "))
        XCTAssertNil(MediaResolver.sanitise("///"))
        XCTAssertNil(MediaResolver.sanitise(" . "))
        XCTAssertEqual(MediaResolver.sanitise("  clip  "), "clip")
        XCTAssertEqual(MediaResolver.sanitise("a/b:c\\d"), "a-b-c-d")
        XCTAssertEqual(MediaResolver.sanitise(String(repeating: "x", count: 400))?.count, 120)
    }

    func testDestinationIsReadFromEitherFinishedLine() {
        let merged = "[youtube] abc: Downloading\n[download] Destination: /tmp/a.webm\n"
            + "Merging formats into \"/tmp/a.mp4\"\nDeleting original file /tmp/a.webm\n"
        XCTAssertEqual(MediaResolver.parseDestination(merged), "/tmp/a.mp4",
                       "the last name yt-dlp printed is the one on disk")
        XCTAssertEqual(MediaResolver.parseDestination("[download] Destination: /tmp/b.webm\n"), "/tmp/b.webm")
        XCTAssertEqual(MediaResolver.parseDestination("[ExtractAudio] Destination: /tmp/c.mp3\n"), "/tmp/c.mp3")
        XCTAssertNil(MediaResolver.parseDestination("[youtube] abc: Downloading\nERROR: unavailable\n"))
    }

    func testEndpointBodyCarriesTheRequest() throws {
        let url = URL(string: "https://example.com/v")!
        let data = try XCTUnwrap(MediaResolver.endpointBody(
            for: url, options: MediaResolveOptions(quality: .p480, mute: true, fileName: "clip")))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["url"], url.absoluteString)
        XCTAssertEqual(json["format"], MediaQuality.p480.formatSelector)
        XCTAssertEqual(json["mute"], "true")
        XCTAssertEqual(json["filename"], "clip")

        let plain = try XCTUnwrap(MediaResolver.endpointBody(
            for: url, options: MediaResolveOptions(fileName: "   ")))
        XCTAssertNil((try JSONSerialization.jsonObject(with: plain) as? [String: String])?["filename"])
    }

    func testFailuresSayWhatToDo() {
        XCTAssertEqual(MediaResolverFailure.notConfigured.message, "Set a yt-dlp path or a resolver endpoint first.")
        XCTAssertEqual(MediaResolverFailure.endpointFailed(503).message, "The resolver endpoint answered 503.")
        XCTAssertFalse(MediaResolverFailure.binaryFailed("").message.isEmpty)
    }

    func testBinaryOutcomeFailsWhenExitCodeIsNonZeroEvenIfDestinationPrinted() {
        let output = "[download] Destination: /tmp/partial.mp4\nERROR: postprocessing failed\n"
        XCTAssertEqual(
            MediaResolveState.binaryOutcome(terminationStatus: 1, output: output),
            .failure(.binaryFailed("ERROR: postprocessing failed"))
        )
    }
}
