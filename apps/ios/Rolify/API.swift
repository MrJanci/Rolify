import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case decodingError(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL ungueltig"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .decodingError(let msg): return "Decode-Fehler: \(msg)"
        case .unauthorized: return "Nicht angemeldet"
        }
    }
}

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let accessTokenTtl: String?
}

struct UserProfile: Codable {
    let id: String
    let email: String
    let displayName: String
    let bio: String?
    let avatarUrl: String?
}

struct TrackListItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let albumId: String
    let coverUrl: String
    let durationMs: Int
}

struct BrowseHomeResponse: Codable {
    let tracks: [TrackListItem]
}

struct StreamManifest: Codable {
    let trackId: String
    let title: String
    let artist: String
    let album: String
    let coverUrl: String
    let durationMs: Int
    let signedCiphertextUrl: String
    let masterKeyHex: String
    let expiresInS: Int
}

/// Thread-safe minimal API-Client. Nutzt in-memory Token-Speicher + UserDefaults als Persistenz.
@Observable
@MainActor
final class API {
    static let shared = API()

    // Produktions-Default ist rolify.rolak.ch. Fuer lokales Dev im LAN kannst du das
    // ueber UserDefaults-Key "rolify.apiBase" ueberschreiben (Einstellungen-Screen spaeter).
    var baseURL: URL {
        if let custom = UserDefaults.standard.string(forKey: "rolify.apiBase"),
           let url = URL(string: custom) { return url }
        return URL(string: "https://rolify.rolak.ch")!
    }

    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: "rolify.deviceId") { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: "rolify.deviceId")
        return fresh
    }

    var isLoggedIn: Bool { accessToken != nil }

    init() {
        accessToken = UserDefaults.standard.string(forKey: "rolify.accessToken")
        refreshToken = UserDefaults.standard.string(forKey: "rolify.refreshToken")
    }

    private func persistTokens(_ t: AuthTokens) {
        self.accessToken = t.accessToken
        self.refreshToken = t.refreshToken
        UserDefaults.standard.set(t.accessToken, forKey: "rolify.accessToken")
        UserDefaults.standard.set(t.refreshToken, forKey: "rolify.refreshToken")
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        UserDefaults.standard.removeObject(forKey: "rolify.accessToken")
        UserDefaults.standard.removeObject(forKey: "rolify.refreshToken")
    }

    // MARK: Auth

    func register(email: String, password: String, displayName: String) async throws -> AuthTokens {
        let body: [String: String] = [
            "email": email, "password": password, "displayName": displayName, "deviceId": deviceId,
        ]
        let tokens: AuthTokens = try await request("/auth/register", method: "POST", body: body, auth: false)
        persistTokens(tokens)
        return tokens
    }

    func login(email: String, password: String) async throws -> AuthTokens {
        let body: [String: String] = ["email": email, "password": password, "deviceId": deviceId]
        let tokens: AuthTokens = try await request("/auth/login", method: "POST", body: body, auth: false)
        persistTokens(tokens)
        return tokens
    }

    func refresh() async throws {
        guard let rt = refreshToken else { throw APIError.unauthorized }
        let body = ["refreshToken": rt]
        let tokens: AuthTokens = try await request("/auth/refresh", method: "POST", body: body, auth: false)
        persistTokens(tokens)
    }

    // MARK: Content

    func me() async throws -> UserProfile {
        try await request("/me", method: "GET")
    }

    func browseHome() async throws -> BrowseHomeResponse {
        try await request("/browse/home", method: "GET")
    }

    func streamManifest(trackId: String) async throws -> StreamManifest {
        try await request("/stream/\(trackId)", method: "GET")
    }

    // MARK: Request-Core

    private func request<T: Decodable>(
        _ path: String, method: String, body: Encodable? = nil, auth: Bool = true
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        if auth {
            guard let token = accessToken else { throw APIError.unauthorized }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.httpError(-1, "no response")
        }
        if http.statusCode == 401 && auth {
            // Transparent refresh attempt
            try await refresh()
            return try await request(path, method: method, body: body, auth: auth)
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(http.statusCode, bodyStr.prefix(400).description)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(String(describing: error))
        }
    }
}

private struct AnyEncodable: Encodable {
    let wrapped: Encodable
    init(_ w: Encodable) { self.wrapped = w }
    func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
}
