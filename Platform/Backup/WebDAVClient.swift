import Foundation

struct WebDAVCredentials: Equatable, Sendable {
    var username: String
    var password: String
}

struct WebDAVResource: Equatable, Sendable {
    var href: String
    var isCollection: Bool
    var contentLength: Int64?
}

enum WebDAVError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case notFound
    case status(Int)
    case malformedResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The WebDAV address is not valid."
        case .unauthorized: return "The server rejected the user name or password."
        case .notFound: return "The file or folder does not exist on the server."
        case .status(let code): return "The WebDAV server answered with status \(code)."
        case .malformedResponse: return "The WebDAV server sent an unreadable response."
        case .transport(let message): return message
        }
    }
}

/// Minimal WebDAV client over `URLSession`: PROPFIND, MKCOL, PUT, GET and DELETE. No dependencies.
struct WebDAVClient: Sendable {
    let baseURL: URL
    let credentials: WebDAVCredentials
    var session: URLSession = .shared

    init(baseURL: URL, credentials: WebDAVCredentials, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.session = session
    }

    init?(serverURL: String, credentials: WebDAVCredentials, session: URLSession = .shared) {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false
        else { return nil }
        self.init(baseURL: url, credentials: credentials, session: session)
    }

    func url(for path: String) -> URL {
        var url = baseURL
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            url.appendPathComponent(String(component), isDirectory: false)
        }
        return url
    }

    func propfind(_ path: String, depth: Int = 1) async throws -> [WebDAVResource] {
        let data = try await perform(
            method: "PROPFIND",
            path: path,
            headers: ["Depth": String(max(0, min(depth, 1))), "Content-Type": "application/xml; charset=utf-8"]
        )
        let parser = WebDAVMultistatusParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { throw WebDAVError.malformedResponse }
        return parser.resources
    }

    func mkcol(_ path: String) async throws {
        do {
            _ = try await perform(method: "MKCOL", path: path, accepted: [200, 201, 204, 405])
        } catch WebDAVError.status(409) {
            throw WebDAVError.notFound
        }
    }

    func put(_ data: Data, to path: String, contentType: String = "application/json") async throws {
        _ = try await perform(
            method: "PUT",
            path: path,
            body: data,
            headers: ["Content-Type": contentType],
            accepted: [200, 201, 204]
        )
    }

    func get(_ path: String) async throws -> Data {
        try await perform(method: "GET", path: path, accepted: [200])
    }

    func delete(_ path: String) async throws {
        _ = try await perform(method: "DELETE", path: path, accepted: [200, 202, 204, 404])
    }

    func exists(_ path: String) async throws -> Bool {
        do {
            _ = try await propfind(path, depth: 0)
            return true
        } catch WebDAVError.notFound {
            return false
        } catch WebDAVError.status(404) {
            return false
        }
    }

    /// Creates every missing component of `path` with MKCOL (405 means it already exists).
    func ensureDirectory(_ path: String) async throws {
        var current = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            current += "/" + component
            try await mkcol(current)
        }
    }

    func checkConnection() async throws {
        _ = try await propfind("", depth: 0)
    }

    private func perform(
        method: String,
        path: String,
        body: Data? = nil,
        headers: [String: String] = [:],
        accepted: Set<Int> = []
    ) async throws -> Data {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if !credentials.username.isEmpty || !credentials.password.isEmpty {
            let token = Data("\(credentials.username):\(credentials.password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WebDAVError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.malformedResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw WebDAVError.unauthorized }
        if http.statusCode == 404 { throw WebDAVError.notFound }
        let ok = accepted.isEmpty ? (200..<300).contains(http.statusCode) : accepted.contains(http.statusCode)
        guard ok else { throw WebDAVError.status(http.statusCode) }
        return data
    }
}

private final class WebDAVMultistatusParser: NSObject, XMLParserDelegate {
    var resources: [WebDAVResource] = []
    private var inResponse = false
    private var currentHref: String?
    private var isCollection = false
    private var contentLength: Int64?
    private var text = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        text = ""
        switch elementName.lowercased() {
        case "response":
            inResponse = true
            currentHref = nil
            isCollection = false
            contentLength = nil
        case "collection":
            if inResponse { isCollection = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if name == "href" && inResponse {
            currentHref = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if name == "getcontentlength" && inResponse {
            contentLength = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if name == "response" && inResponse {
            if let href = currentHref, !href.isEmpty {
                resources.append(WebDAVResource(href: href, isCollection: isCollection, contentLength: contentLength))
            }
            inResponse = false
        }
        text = ""
    }
}
