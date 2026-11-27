import XCTest
@testable import KatiKati

/// W-10: the control socket, exercised over a real UNIX socket rather than by calling `parse`.
///
/// The server runs on an injected temp path against a spy target, so nothing here needs the window
/// manager, Accessibility, or a display. Each test connects as a client would (`nc -U`, the CLI),
/// writes one newline-framed line and reads one line back.
final class WorkspaceControlServerTests: XCTestCase {

    // MARK: - Protocol

    @MainActor
    func testStatusRoundTripOverTheSocket() async throws {
        let harness = try ControlHarness()
        defer { harness.stop() }

        harness.target.statusReply = "ok workspaces=on tiling=on display=stub workspace=4 windows=2"
        let reply = try await harness.send("status")
        XCTAssertEqual(reply, "ok workspaces=on tiling=on display=stub workspace=4 windows=2")
        XCTAssertEqual(harness.target.commands, [.status])
    }

    @MainActor
    func testUnknownVerbIsRejectedWithoutReachingTheTarget() async throws {
        let harness = try ControlHarness()
        defer { harness.stop() }

        let reply = try await harness.send("frobnicate 3")
        XCTAssertTrue(reply.hasPrefix("error unknown command"), reply)
        XCTAssertEqual(harness.target.commands, [])
    }

    @MainActor
    func testOversizedRequestIsRejected() async throws {
        let harness = try ControlHarness()
        defer { harness.stop() }

        // Past the cap with no newline: the server must refuse it whole rather than act on a
        // truncated line.
        let request = String(repeating: "a", count: WorkspaceControlServer.maxRequestBytes + 512)
        let reply = try await harness.send(request)
        XCTAssertEqual(reply, "error request too large")
        XCTAssertEqual(harness.target.commands, [])
    }

    @MainActor
    func testRequestAtTheCapStillParses() async throws {
        let harness = try ControlHarness()
        defer { harness.stop() }

        let padding = String(repeating: " ", count: WorkspaceControlServer.maxRequestBytes - "status".utf8.count - 1)
        let reply = try await harness.send("status" + padding)
        XCTAssertTrue(reply.hasPrefix("ok"), reply)
        XCTAssertEqual(harness.target.commands, [.status])
    }

    // MARK: - Socket hygiene

    @MainActor
    func testSocketFileIsUserOnly() throws {
        let harness = try ControlHarness()
        defer { harness.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: harness.socketURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }

    @MainActor
    func testSecondListenerOnTheSamePathIsRejectedByTheLock() throws {
        let harness = try ControlHarness()
        defer { harness.stop() }

        let second = WorkspaceControlServer(socketURL: harness.socketURL, target: SpyControlTarget())
        second.start()
        defer { second.stop() }
        XCTAssertFalse(second.isListening, "the lock must refuse a second listener on the same path")
        XCTAssertTrue(harness.server.isListening, "the first listener must be untouched")
    }

    // MARK: - Commands reach the target

    @MainActor
    func testSwitchAndMoveReachTheTargetForNumberedAndNamedWorkspaces() async throws {
        let harness = try ControlHarness()
        defer { harness.stop() }

        let switched = try await harness.send("switch 3")
        XCTAssertEqual(switched, "ok switch 3")
        let moved = try await harness.send("move D")
        XCTAssertEqual(moved, "ok move D")
        let tenth = try await harness.send("switch 10")
        XCTAssertEqual(tenth, "ok switch 10")
        XCTAssertEqual(
            harness.target.commands,
            [.switchTo(.numbered(3)), .moveTo(.named("D")), .switchTo(.numbered(10))]
        )
    }

    @MainActor
    func testInvalidWorkspaceIsAnArgumentErrorNotASwitch() async throws {
        let harness = try ControlHarness()
        defer { harness.stop() }

        let reply = try await harness.send("switch 11")
        XCTAssertEqual(reply, "error expected a workspace 1-10 or A-Z")
        XCTAssertEqual(harness.target.commands, [])
    }

    @MainActor
    func testLayoutPresetIsValidated() async throws {
        let harness = try ControlHarness()
        defer { harness.stop() }

        let applied = try await harness.send("layout ribbon")
        XCTAssertEqual(applied, "ok layout ribbon")
        XCTAssertEqual(harness.target.commands, [.layout(.ribbon)])

        let bad = try await harness.send("layout nope")
        XCTAssertTrue(bad.hasPrefix("error expected a preset"), bad)
        XCTAssertEqual(harness.target.commands, [.layout(.ribbon)])
    }
}

/// One server on a temp socket plus the spy it talks to.
@MainActor
private final class ControlHarness {
    let directory: URL
    let socketURL: URL
    let server: WorkspaceControlServer
    let target: SpyControlTarget

    init() throws {
        // Short on purpose: `sun_path` is 104 bytes on macOS, and the per-user temp directory plus a
        // full UUID overflows it. The socket must live somewhere short to be bindable at all.
        directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("kkctl-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        socketURL = directory.appendingPathComponent("control.sock")
        target = SpyControlTarget()
        server = WorkspaceControlServer(socketURL: socketURL, target: target)
        server.start()
        XCTAssertTrue(server.isListening, "server should own the socket after start()")
    }

    func stop() {
        server.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    /// One newline-framed request, one line back — the same exchange `nc -U` makes.
    func send(_ request: String) async throws -> String {
        let path = socketURL.path
        let payload = request.hasSuffix("\n") ? request : request + "\n"
        return try await withCheckedThrowingContinuation { continuation in
            // Off the main actor: the blocking connect/read must not starve the server's MainActor
            // hop, which is what turns a request into a reply.
            DispatchQueue.global().async {
                do {
                    continuation.resume(returning: try Self.roundTrip(path: path, payload: payload))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func roundTrip(path: String, payload: String) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlSocketError.socket }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw ControlSocketError.pathTooLong
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                connect(fd, addressPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw ControlSocketError.connect }

        let out = Array(payload.utf8)
        _ = out.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = Darwin.read(fd, &buffer, buffer.count)
        guard count > 0 else { throw ControlSocketError.emptyReply }
        return String(decoding: buffer[0..<count], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum ControlSocketError: Error {
        case socket, pathTooLong, connect, emptyReply
    }
}

/// Records what actually arrived at the far end of the socket.
@MainActor
private final class SpyControlTarget: WorkspaceControlTarget {
    var commands: [WorkspaceControlCommand] = []
    var statusReply = "ok status=stubbed"

    func perform(_ command: WorkspaceControlCommand) -> String {
        commands.append(command)
        switch command {
        case .status: return statusReply
        case .switchTo(let workspace): return "ok switch \(workspace.token)"
        case .moveTo(let workspace): return "ok move \(workspace.token)"
        case .layout(let preset): return "ok layout \(preset.rawValue)"
        case .pause: return "ok paused"
        case .resume: return "ok resumed"
        case .retile: return "ok retiled"
        }
    }
}
