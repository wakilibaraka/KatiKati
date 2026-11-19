import Foundation
import XCTest

// MARK: - URLProtocol mock

struct MockHTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

struct MockRecordedRequest {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?

    var authorization: String? { value("Authorization") }
    var depth: String? { value("Depth") }

    private func value(_ field: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
    }
}

/// Serves `URLSession` requests from an in-memory WebDAV server, so client and backup tests
/// run without a network, a real server or Keychain access.
final class MockWebDAVURLProtocol: URLProtocol {
    static var handler: ((URLRequest, Data?) throws -> MockHTTPResponse)?
    static var recorded: [MockRecordedRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.bodyData(from: request)
        Self.recorded.append(MockRecordedRequest(
            method: request.httpMethod ?? "GET",
            url: request.url ?? URL(string: "https://dav.example.test")!,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        ))
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let result = try handler(request, body)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: result.status,
                    httpVersion: "HTTP/1.1",
                    headerFields: result.headers
                  )
            else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !result.body.isEmpty {
                client?.urlProtocol(self, didLoad: result.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// `URLSession` may move a request body into `httpBodyStream` before it reaches URLProtocol.
    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                stream.read(pointer.baseAddress!, maxLength: pointer.count)
            }
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data.isEmpty ? nil : data
    }
}

/// Minimal in-memory WebDAV server: MKCOL, PUT, GET, DELETE and PROPFIND with Basic auth.
final class MockWebDAVServer: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var directories: Set<String> = ["/"]
    let rootPath: String

    private let expectedAuthorization = "Basic " + Data("tester:secret".utf8).base64EncodedString()

    init(rootPath: String) {
        self.rootPath = rootPath
        var path = rootPath
        while path != "/", !path.isEmpty {
            directories.insert(path)
            path = (path as NSString).deletingLastPathComponent
        }
    }

    func file(at path: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return files[path]
    }

    func handle(_ request: URLRequest, body: Data?) -> MockHTTPResponse {
        let path = request.url?.path ?? "/"
        let method = request.httpMethod ?? "GET"
        lock.lock()
        defer { lock.unlock() }

        guard request.value(forHTTPHeaderField: "Authorization") == expectedAuthorization else {
            return MockHTTPResponse(status: 401)
        }

        switch method {
        case "PROPFIND":
            guard directories.contains(path) || files[path] != nil else {
                return MockHTTPResponse(status: 404)
            }
            let isCollection = directories.contains(path)
            let length = files[path]?.count ?? 0
            let xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <d:multistatus xmlns:d="DAV:">
              <d:response>
                <d:href>\(path)</d:href>
                <d:propstat>
                  <d:prop>
                    <d:resourcetype>\(isCollection ? "<d:collection/>" : "")</d:resourcetype>
                    <d:getcontentlength>\(length)</d:getcontentlength>
                  </d:prop>
                  <d:status>HTTP/1.1 200 OK</d:status>
                </d:propstat>
              </d:response>
            </d:multistatus>
            """
            return MockHTTPResponse(
                status: 207,
                headers: ["Content-Type": "application/xml; charset=utf-8"],
                body: Data(xml.utf8)
            )
        case "MKCOL":
            if directories.contains(path) || files[path] != nil {
                return MockHTTPResponse(status: 405)
            }
            let parent = (path as NSString).deletingLastPathComponent
            guard directories.contains(parent) else {
                return MockHTTPResponse(status: 409)
            }
            directories.insert(path)
            return MockHTTPResponse(status: 201)
        case "PUT":
            let parent = (path as NSString).deletingLastPathComponent
            guard directories.contains(parent) else {
                return MockHTTPResponse(status: 409)
            }
            files[path] = body ?? Data()
            return MockHTTPResponse(status: 201)
        case "GET":
            guard let data = files[path] else {
                return MockHTTPResponse(status: 404)
            }
            return MockHTTPResponse(status: 200, body: data)
        case "DELETE":
            if files.removeValue(forKey: path) != nil {
                return MockHTTPResponse(status: 204)
            }
            if path != rootPath, directories.remove(path) != nil {
                return MockHTTPResponse(status: 204)
            }
            return MockHTTPResponse(status: 404)
        default:
            return MockHTTPResponse(status: 405)
        }
    }
}

// MARK: - Client

final class WebDAVClientTests: XCTestCase {
    private var session: URLSession!

    override func setUpWithError() throws {
        try super.setUpWithError()
        MockWebDAVURLProtocol.handler = nil
        MockWebDAVURLProtocol.recorded = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWebDAVURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDownWithError() throws {
        session.invalidateAndCancel()
        MockWebDAVURLProtocol.handler = nil
        MockWebDAVURLProtocol.recorded = []
        try super.tearDownWithError()
    }

    private var client: WebDAVClient {
        WebDAVClient(
            baseURL: URL(string: "https://dav.example.test/dav")!,
            credentials: WebDAVCredentials(username: "tester", password: "secret"),
            session: session
        )
    }

    private var basicAuthorization: String {
        "Basic " + Data("tester:secret".utf8).base64EncodedString()
    }

    private func respond(_ response: MockHTTPResponse) {
        MockWebDAVURLProtocol.handler = { _, _ in response }
    }

    private func assertWebDAVError(
        _ expected: WebDAVError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as WebDAVError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func testPropfindParsesNamespacedMultistatus() async throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/Sync/</d:href>
            <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/Sync/todos.json</d:href>
            <d:propstat><d:prop><d:resourcetype/><d:getcontentlength>42</d:getcontentlength></d:prop></d:propstat>
          </d:response>
        </d:multistatus>
        """
        respond(MockHTTPResponse(status: 207, body: Data(xml.utf8)))

        let resources = try await client.propfind("/Sync", depth: 1)

        XCTAssertEqual(resources, [
            WebDAVResource(href: "/dav/Sync/", isCollection: true, contentLength: nil),
            WebDAVResource(href: "/dav/Sync/todos.json", isCollection: false, contentLength: 42),
        ])
        let request = try XCTUnwrap(MockWebDAVURLProtocol.recorded.first)
        XCTAssertEqual(request.method, "PROPFIND")
        XCTAssertEqual(request.url.path, "/dav/Sync")
        XCTAssertEqual(request.depth, "1")
        XCTAssertEqual(request.headers["Content-Type"], "application/xml; charset=utf-8")
        XCTAssertEqual(request.authorization, basicAuthorization)
    }

    func testPutSendsBodyAndContentType() async throws {
        respond(MockHTTPResponse(status: 201))
        let payload = Data(#"{"hello":"world"}"#.utf8)

        try await client.put(payload, to: "/Sync/todos.json")

        let request = try XCTUnwrap(MockWebDAVURLProtocol.recorded.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url.path, "/dav/Sync/todos.json")
        XCTAssertEqual(request.body, payload)
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(request.authorization, basicAuthorization)
    }

    func testHTTPStatusesMapToDomainErrors() async {
        MockWebDAVURLProtocol.handler = { request, _ in
            switch request.url?.path {
            case "/dav/missing": return MockHTTPResponse(status: 404)
            case "/dav/private": return MockHTTPResponse(status: 401)
            default: return MockHTTPResponse(status: 500)
            }
        }

        await assertWebDAVError(.notFound) { _ = try await client.get("/missing") }
        await assertWebDAVError(.unauthorized) { _ = try await client.get("/private") }
        await assertWebDAVError(.status(500)) { _ = try await client.get("/broken") }
    }

    func testMkcolAcceptsExistingDirectoryAndMapsMissingParent() async {
        MockWebDAVURLProtocol.handler = { request, _ in
            request.url?.path == "/dav/existing"
                ? MockHTTPResponse(status: 405)
                : MockHTTPResponse(status: 409)
        }

        do {
            try await client.mkcol("/existing")
        } catch {
            XCTFail("405 means the collection already exists: \(error)")
        }
        await assertWebDAVError(.notFound) { try await client.mkcol("/missing/child") }
    }

    func testEnsureDirectoryCreatesEveryComponent() async throws {
        respond(MockHTTPResponse(status: 201))

        try await client.ensureDirectory("/KatiKati/devices/mac")

        XCTAssertEqual(MockWebDAVURLProtocol.recorded.map(\.url.path), [
            "/dav/KatiKati",
            "/dav/KatiKati/devices",
            "/dav/KatiKati/devices/mac",
        ])
        XCTAssertTrue(MockWebDAVURLProtocol.recorded.allSatisfy { $0.method == "MKCOL" })
    }

    func testExistsUsesZeroDepthAndTreats404AsMissing() async throws {
        let xml = """
        <d:multistatus xmlns:d="DAV:"><d:response><d:href>/dav/present</d:href></d:response></d:multistatus>
        """
        MockWebDAVURLProtocol.handler = { request, _ in
            request.url?.path == "/dav/present"
                ? MockHTTPResponse(status: 207, body: Data(xml.utf8))
                : MockHTTPResponse(status: 404)
        }

        let present = try await client.exists("/present")
        let absent = try await client.exists("/absent")
        XCTAssertTrue(present)
        XCTAssertFalse(absent)
        XCTAssertEqual(MockWebDAVURLProtocol.recorded.map(\.depth), ["0", "0"])
    }

    func testDeleteTreats404AsAlreadyGone() async throws {
        respond(MockHTTPResponse(status: 404))

        try await client.delete("/Sync/gone.json")

        XCTAssertEqual(MockWebDAVURLProtocol.recorded.first?.method, "DELETE")
    }

    func testMalformedMultistatusIsRejected() async {
        respond(MockHTTPResponse(status: 207, body: Data("<d:multistatus><d:response>".utf8)))

        await assertWebDAVError(.malformedResponse) { _ = try await client.propfind("/Sync") }
    }

    func testTransportFailureIsWrapped() async {
        MockWebDAVURLProtocol.handler = { _, _ in throw URLError(.timedOut) }

        await assertWebDAVError(.transport(URLError(.timedOut).localizedDescription)) {
            _ = try await client.get("/Sync/todos.json")
        }
    }
}

// MARK: - Backup service end to end

@MainActor
final class WebDAVBackupServiceTests: XCTestCase {
    private struct Environment {
        let service: WebDAVBackupService
        let server: MockWebDAVServer
        let directory: URL
        let defaults: UserDefaults
        let suite: String
        let session: URLSession
    }

    private func makeEnvironment(restoreMode: WebDAVRestoreMode = .merge) throws -> Environment {
        let suite = "katikati.webdav.e2e.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("webdav-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWebDAVURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let server = MockWebDAVServer(rootPath: "/dav")
        MockWebDAVURLProtocol.recorded = []
        MockWebDAVURLProtocol.handler = { request, body in server.handle(request, body: body) }

        let service = WebDAVBackupService(
            defaults: defaults,
            supportDirectory: directory,
            session: session,
            passwordOverride: "secret"
        )
        service.serverURL = "https://dav.example.test/dav"
        service.username = "tester"
        service.settings.deviceName = "Test Mac"
        service.settings.remoteRoot = "/KatiKatiSync"
        service.settings.enabledDomains = [.todos]
        service.settings.restoreMode = restoreMode

        return Environment(
            service: service,
            server: server,
            directory: directory,
            defaults: defaults,
            suite: suite,
            session: session
        )
    }

    private func cleanUp(_ environment: Environment) {
        environment.session.invalidateAndCancel()
        environment.defaults.removePersistentDomain(forName: environment.suite)
        try? FileManager.default.removeItem(at: environment.directory)
        MockWebDAVURLProtocol.handler = nil
        MockWebDAVURLProtocol.recorded = []
    }

    private var basicAuthorization: String {
        "Basic " + Data("tester:secret".utf8).base64EncodedString()
    }

    func testTestConnectionUsesMockServerWithoutKeychain() async throws {
        let environment = try makeEnvironment()
        defer { cleanUp(environment) }

        await environment.service.testConnection()

        guard case .success = environment.service.status else {
            XCTFail("Connection failed: \(environment.service.status)")
            return
        }
        let request = try XCTUnwrap(MockWebDAVURLProtocol.recorded.first)
        XCTAssertEqual(request.method, "PROPFIND")
        XCTAssertEqual(request.depth, "0")
        XCTAssertEqual(request.authorization, basicAuthorization)
    }

    func testBackupThenSnapshotRestoreRoundTripsThroughMockServer() async throws {
        let environment = try makeEnvironment(restoreMode: .snapshotFaithful)
        defer { cleanUp(environment) }

        let tasksURL = environment.directory.appendingPathComponent("tasks.json")
        let original = Data(#"[{"id":"local","name":"Local"}]"#.utf8)
        try original.write(to: tasksURL, options: .atomic)

        await environment.service.backupNow()

        guard case .success = environment.service.status else {
            XCTFail("Backup failed: \(environment.service.status)")
            return
        }
        let remotePath = "/dav/KatiKatiSync/test-mac/todos.json"
        let remoteData = try XCTUnwrap(environment.server.file(at: remotePath))
        let envelope = try JSONDecoder().decode(WebDAVSyncEnvelope.self, from: remoteData)
        XCTAssertEqual(envelope.domain, .todos)
        XCTAssertEqual(envelope.files["tasks.json"], original)
        XCTAssertNotNil(
            environment.server.file(at: "/dav/KatiKatiSync/test-mac/manifest.json"),
            "backup writes a manifest beside the domain files"
        )

        let changedLocally = Data(#"[{"id":"local","name":"Changed locally"}]"#.utf8)
        try changedLocally.write(to: tasksURL, options: .atomic)

        await environment.service.restoreNow()

        guard case .success = environment.service.status else {
            XCTFail("Restore failed: \(environment.service.status)")
            return
        }
        XCTAssertEqual(try Data(contentsOf: tasksURL), original, "snapshot restore replaces local todos")
        let safetyFiles = try FileManager.default.contentsOfDirectory(
            at: environment.directory.appendingPathComponent("Backups"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(safetyFiles.count, 1)
        let safety = try SettingsBackupFile.decode(Data(contentsOf: try XCTUnwrap(safetyFiles.first)))
        XCTAssertEqual(safety.files["tasks.json"], changedLocally, "the safety copy holds the pre-restore local todos")

        let methods = MockWebDAVURLProtocol.recorded.map(\.method)
        XCTAssertTrue(methods.contains("MKCOL"))
        XCTAssertTrue(methods.contains("PUT"))
        XCTAssertTrue(methods.contains("GET"))
        XCTAssertTrue(MockWebDAVURLProtocol.recorded.allSatisfy { $0.authorization == basicAuthorization })
    }

    func testRestoreWithNoRemoteFilesFailsBeforeWritingLocally() async throws {
        let environment = try makeEnvironment()
        defer { cleanUp(environment) }

        await environment.service.restoreNow()

        XCTAssertEqual(
            environment.service.status,
            .failure(WebDAVBackupService.ServiceError.noRemoteData.localizedDescription)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: environment.directory.appendingPathComponent("Backups").path),
            "nothing was restored, so no safety copy was needed"
        )
        XCTAssertFalse(MockWebDAVURLProtocol.recorded.contains { $0.method == "PUT" })
    }
}
