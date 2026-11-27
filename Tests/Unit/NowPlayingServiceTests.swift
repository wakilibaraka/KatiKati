import XCTest
@testable import KatiKati

@MainActor
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
        // Phase 45: the verdict starts "nothing to say" and is only ever raised by a real reading or a
        // real refusal — the surfaces must not accuse anyone of a missing permission they have not hit.
        XCTAssertEqual(service.playerAccess, .unknown)
    }
    
    /// Ensure togglePlayPause does not crash.
    func testTogglePlayPause() {
        let service = NowPlayingService()
        service.togglePlayPause()
        // No assertions possible without mocking MediaRemote, but this confirms
        // the function is callable.
    }

    func testSharedSingletonPipeEOFGuardAndAudioOutputCache() {
        XCTAssertTrue(NowPlayingService.shared === NowPlayingService.shared)
        XCTAssertTrue(NowPlayingHelper.shouldClearReadabilityHandler(for: Data()))
        XCTAssertFalse(NowPlayingHelper.shouldClearReadabilityHandler(for: Data("{}".utf8)))

        AudioOutputSwitcher.invalidateCache()
        let first = AudioOutputSwitcher.devices(input: false)
        let second = AudioOutputSwitcher.devices(input: false)
        XCTAssertEqual(first, second)
    }

    func testPerAppAudioEngineTeardownRollbackAndPIDReplacement() {
        final class FakeSession: PerAppAudioSession {
            let key: String
            var gains: [Float] = []
            var teardownCount = 0
            init(key: String, initialGain: Float) {
                self.key = key
                self.gains.append(initialGain)
            }
            func setGain(_ value: Float) { gains.append(value) }
            func teardown() { teardownCount += 1 }
        }

        var created: [FakeSession] = []
        var shouldFail = false
        let engine = PerAppAudioEngine { process, gain in
            if shouldFail { throw PerAppAudioFailure.tap }
            let session = FakeSession(key: process.storageKey, initialGain: gain)
            created.append(session)
            return session
        }

        let appA = AppAudioProcess(id: 10, pid: 100, bundleID: "com.test.a", name: "AppA", isRunningOutput: true)
        let appB = AppAudioProcess(id: 11, pid: 100, bundleID: "com.test.b", name: "AppB", isRunningOutput: true)

        engine.setGain(0.5, for: appA)
        XCTAssertTrue(engine.isRouted(appA))
        XCTAssertEqual(created.count, 1)

        // Adjusting same process updates gain in place.
        engine.setGain(0.25, for: appA)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created[0].gains.last, 0.25)

        // Setting unity (1.0) tears down session.
        engine.setGain(1.0, for: appA)
        XCTAssertFalse(engine.isRouted(appA))
        XCTAssertEqual(created[0].teardownCount, 1)

        // Replacing same PID with different bundle key tears down previous session.
        engine.setGain(0.5, for: appA)
        engine.setGain(0.4, for: appB)
        XCTAssertEqual(created[1].teardownCount, 1)
        XCTAssertTrue(engine.isRouted(appB))

        // Failure rolls back mix state cleanly.
        shouldFail = true
        let appC = AppAudioProcess(id: 12, pid: 200, bundleID: "com.test.c", name: "AppC", isRunningOutput: true)
        engine.setGain(0.5, for: appC)
        XCTAssertEqual(engine.failure(for: appC), .tap)
        XCTAssertEqual(engine.gain(for: appC), 1.0)
        XCTAssertFalse(engine.isRouted(appC))

        // Stop tears down all active sessions.
        engine.stop()
        XCTAssertTrue(engine.routing.isEmpty)
        XCTAssertEqual(created[2].teardownCount, 1)
    }
}
