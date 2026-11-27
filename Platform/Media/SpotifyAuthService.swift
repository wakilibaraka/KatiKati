import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// Opt-in Spotify Web API PKCE OAuth client for saving/liking tracks directly to the user's Spotify library
/// and reading active playback / Spotify track URLs. Stores tokens in the macOS Keychain; never runs unless
/// the user enables Spotify OAuth and enters their Spotify Developer Client ID in Settings.
@MainActor
final class SpotifyAuthService: NSObject, ObservableObject {
    static let shared = SpotifyAuthService()

    static let clientIDKey = "com.katikati.dockII.spotifyClientID"
    static let callbackScheme = "katikati"
    static let redirectURI = "katikati://spotify-callback"
    private static let keychainService = "com.katikati.spotify.oauth"
    private static let keychainAccount = "tokens-v1"

    struct StoredTokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
    }

    @Published private(set) var isSignedIn = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var lastError: String?

    private var tokens: StoredTokens?
    private var authSession: ASWebAuthenticationSession?

    var clientID: String {
        get { UserDefaults.standard.string(forKey: Self.clientIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.clientIDKey) }
    }

    override private init() {
        super.init()
        tokens = Self.loadTokens()
        isSignedIn = tokens != nil
    }

    func signIn() {
        let cid = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else {
            lastError = String(localized: "Enter a Spotify Client ID first.")
            return
        }
        guard !isAuthenticating else { return }
        lastError = nil
        isAuthenticating = true

        let verifier = Self.randomVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: cid),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "user-library-read user-library-modify user-read-playback-state")
        ]
        guard let url = comps.url else {
            isAuthenticating = false
            return
        }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.authSession = nil
                if let error {
                    self.isAuthenticating = false
                    self.lastError = error.localizedDescription
                    return
                }
                guard let callbackURL,
                      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
                      items.first(where: { $0.name == "state" })?.value == state,
                      let code = items.first(where: { $0.name == "code" })?.value
                else {
                    self.isAuthenticating = false
                    self.lastError = String(localized: "Spotify authorization returned an invalid response.")
                    return
                }
                await self.exchangeCode(code, verifier: verifier, clientID: cid)
                self.isAuthenticating = false
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    private var refreshTask: Task<String?, Never>?

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        isSignedIn = false
        lastError = nil
        Self.deleteTokens()
    }

    func validAccessToken() async -> String? {
        guard let current = tokens else { return nil }
        if current.expiresAt.timeIntervalSinceNow > 60 {
            return current.accessToken
        }
        if let refreshTask {
            return await refreshTask.value
        }
        guard let refresh = current.refreshToken, !clientID.isEmpty else {
            return nil
        }
        let cid = clientID
        let task = Task { @MainActor [weak self] () -> String? in
            guard let self else { return nil }
            defer { self.refreshTask = nil }
            guard let refreshed = await Self.refreshTokens(refreshToken: refresh, clientID: cid),
                  !Task.isCancelled,
                  self.tokens != nil
            else {
                return nil
            }
            self.tokens = refreshed
            Self.saveTokens(refreshed)
            return refreshed.accessToken
        }
        refreshTask = task
        return await task.value
    }

    func searchTrackID(title: String, artist: String?) async -> (id: String, webURL: URL?)? {
        guard let token = await validAccessToken() else { return nil }
        let queryText = [title, artist].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !queryText.isEmpty else { return nil }
        var comps = URLComponents(string: "https://api.spotify.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: queryText),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tracks = json["tracks"] as? [String: Any],
              let items = tracks["items"] as? [[String: Any]],
              let first = items.first,
              let id = first["id"] as? String
        else {
            return nil
        }
        let external = (first["external_urls"] as? [String: Any])?["spotify"] as? String
        return (id, external.flatMap(URL.init(string:)))
    }

    func isTrackSaved(trackID: String) async -> Bool? {
        guard let token = await validAccessToken() else { return nil }
        var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks/contains")!
        comps.queryItems = [URLQueryItem(name: "ids", value: trackID)]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let array = try? JSONSerialization.jsonObject(with: data) as? [Bool]
        else {
            return nil
        }
        return array.first
    }

    func setTrackSaved(_ saved: Bool, trackID: String) async -> Bool {
        guard let token = await validAccessToken() else { return false }
        var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")!
        comps.queryItems = [URLQueryItem(name: "ids", value: trackID)]
        guard let url = comps.url else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = saved ? "PUT" : "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(code)
        else {
            return false
        }
        return true
    }

    /// Reads the signed-in user's Up Next queue via Spotify Web API (`/v1/me/player/queue`) for L2 / D4.
    func fetchQueue() async -> [MusicQueueEntry] {
        guard let token = await validAccessToken(),
              let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else {
            return []
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queue = json["queue"] as? [[String: Any]]
        else {
            return []
        }

        var entries: [MusicQueueEntry] = []
        var seen = Set<String>()
        for item in queue {
            guard let title = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            let artists = (item["artists"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
                .joined(separator: ", ")
            let entry = MusicQueueEntry(title: title, artist: artists.isEmpty ? nil : artists)
            guard seen.insert(entry.key).inserted else { continue }
            entries.append(entry)
            if entries.count >= 12 { break }
        }
        return entries
    }

    // MARK: Token exchange & Keychain

    private func exchangeCode(_ code: String, verifier: String, clientID: String) async {
        let body = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier
        ]
        guard let exchanged = await Self.postTokenRequest(params: body) else {
            lastError = String(localized: "Failed to exchange Spotify authorization code.")
            return
        }
        tokens = exchanged
        isSignedIn = true
        Self.saveTokens(exchanged)
    }

    private static func refreshTokens(refreshToken: String, clientID: String) async -> StoredTokens? {
        let body = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        guard var refreshed = await postTokenRequest(params: body) else { return nil }
        if refreshed.refreshToken == nil {
            refreshed.refreshToken = refreshToken
        }
        return refreshed
    }

    private static func postTokenRequest(params: [String: String]) async -> StoredTokens? {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else {
            return nil
        }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        return StoredTokens(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private static func loadTokens() -> StoredTokens? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    private static func saveTokens(_ tokens: StoredTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        deleteTokens()
        var add = keychainQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(add as CFDictionary, nil)
    }

    private static func deleteTokens() {
        _ = SecItemDelete(keychainQuery as CFDictionary)
    }
}

extension SpotifyAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first(where: \.isVisible) ?? NSWindow()
    }
}
