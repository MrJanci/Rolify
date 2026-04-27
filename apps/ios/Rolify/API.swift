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
    let quickAccess: [QuickAccessTile]?
    let shelves: [HomeShelf]?
    let tracks: [TrackListItem]   // legacy/fallback
}

/// Spotify-Style Quick-Access-Tile (2x4 Grid oben in Home).
struct QuickAccessTile: Codable, Identifiable, Hashable {
    let id: String
    let kind: String  // "playlist" | "album" | "liked" | "artist"
    let title: String
    let coverUrl: String
    let subtitle: String?
}

/// Recommended Station (Last.fm-based artist-radio).
struct StationItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let coverUrl: String
    let tintHex: String
}

struct HomeShelf: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let tracks: [TrackListItem]?
    let playlists: [PlaylistSummary]?
    let albums: [AlbumListItem]?
    let stations: [StationItem]?
}

struct ArtistListItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let imageUrl: String?
}

struct AlbumListItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let coverUrl: String
    let releaseYear: Int
}

struct SearchResponse: Codable {
    let tracks: [TrackListItem]
    let artists: [ArtistListItem]
    let albums: [AlbumListItem]
}

struct PlaylistSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let coverUrl: String
    let isPublic: Bool
    let trackCount: Int
    var isCollaborative: Bool? = false
    var isMixed: Bool? = false
    var isOwned: Bool? = true
    var isDynamic: Bool? = false
    var dynamicSource: String? = nil
}

struct PlaylistDetail: Codable, Hashable {
    let id: String
    let name: String
    let description: String?
    let coverUrl: String
    let isPublic: Bool
    let ownerId: String
    let tracks: [PlaylistTrackItem]
    var isCollaborative: Bool? = false
    var isMixed: Bool? = false
    var isOwned: Bool? = true
    var canEdit: Bool? = true
    var collaborators: [CollaboratorInfo]? = nil
}

struct CollaboratorInfo: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let avatarUrl: String?
    let role: String  // EDITOR / VIEWER
}

struct PlaylistTrackItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let artistId: String
    let album: String
    let albumId: String
    let coverUrl: String
    let durationMs: Int
    let position: Int
}

struct AlbumTrackItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let durationMs: Int
    let trackNumber: Int
    let artist: String
    let artistId: String
    let album: String
    let albumId: String
    let coverUrl: String
}

struct ArtistSummary: Codable, Hashable {
    let id: String
    let name: String
    let imageUrl: String?
}

struct AlbumDetail: Codable, Hashable {
    let id: String
    let title: String
    let coverUrl: String
    let releaseYear: Int
    let artist: ArtistSummary
    let tracks: [AlbumTrackItem]
}

struct ArtistDetail: Codable, Hashable {
    let id: String
    let name: String
    let imageUrl: String
    let topTracks: [AlbumTrackItem]
    let albums: [AlbumListItem]
}

struct ScrapeJob: Codable, Identifiable, Hashable {
    let id: String
    let playlistUrl: String
    let status: String    // QUEUED / RUNNING / DONE / FAILED
    let totalTracks: Int
    let processedTracks: Int
    let failedTracks: Int
    let errorMessage: String?
    let createdAt: String
    let startedAt: String?
    let completedAt: String?
}

struct ScrapeJobsResponse: Codable {
    let jobs: [ScrapeJob]
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

    /// Track-Start melden fuer "Jump back in" Home-Shelf.
    /// Backend dedupes identical trackIds innerhalb 30s.
    /// Fire-and-forget — Errors werden vom Caller ignoriert.
    func logPlayHistory(trackId: String, contextType: String? = nil, contextId: String? = nil) async throws {
        struct Body: Encodable { let trackId: String; let contextType: String?; let contextId: String? }
        struct Resp: Codable { let status: String; let id: String? }
        let _: Resp = try await request("/play-history", method: "POST",
                                        body: Body(trackId: trackId, contextType: contextType, contextId: contextId))
    }

    struct AllTracksResponse: Codable { let tracks: [TrackListItem] }

    /// Alle verfuegbaren Tracks im System (flat, paginated).
    /// Fuer Library-"Alle Songs"-Filter — zeigt auch gescrapete Tracks die noch
    /// in keiner Playlist sind.
    func allTracks(limit: Int = 200, offset: Int = 0) async throws -> [TrackListItem] {
        let r: AllTracksResponse = try await request("/tracks?limit=\(limit)&offset=\(offset)", method: "GET")
        return r.tracks
    }

    func streamManifest(trackId: String) async throws -> StreamManifest {
        try await request("/stream/\(trackId)", method: "GET")
    }

    func search(q: String) async throws -> SearchResponse {
        // Query-String sauber ueber URLComponents bauen — vermeidet ?-Encoding-Bug
        // von appendingPathComponent.
        var comps = URLComponents()
        comps.queryItems = [URLQueryItem(name: "q", value: q)]
        let qs = comps.percentEncodedQuery ?? ""
        return try await requestPath("/search?\(qs)", method: "GET")
    }

    // MARK: External Search (Spotify Catalog)

    struct ExternalSearchResponse: Codable {
        struct Hit: Codable, Identifiable, Hashable {
            let spotifyId: String
            let localId: String?
            let title: String
            let artist: String
            let album: String
            let albumId: String
            let coverUrl: String
            let durationMs: Int
            let isDownloaded: Bool
            let isLiked: Bool
            let isQueued: Bool
            var id: String { spotifyId }
        }
        let tracks: [Hit]
    }

    func externalSearch(q: String) async throws -> [ExternalSearchResponse.Hit] {
        var comps = URLComponents()
        comps.queryItems = [URLQueryItem(name: "q", value: q)]
        let qs = comps.percentEncodedQuery ?? ""
        let r: ExternalSearchResponse = try await requestPath("/search/external?\(qs)", method: "GET")
        return r.tracks
    }

    struct DownloadExternalResponse: Codable {
        let status: String  // queued / already_queued / already_downloaded
        let jobId: String?
        let localId: String?
    }

    @discardableResult
    func downloadExternalTrack(spotifyId: String) async throws -> DownloadExternalResponse {
        try await request("/search/external/\(spotifyId)/download", method: "POST")
    }

    /// Spotify-Album-Tracks fuer Album-Detail-Discover. Selbe Hit-Shape wie /search/external.
    /// Returns [] bei API-Fehler (Spotify down etc.).
    func discoverAlbumTracks(albumId: String) async throws -> [ExternalSearchResponse.Hit] {
        let r: ExternalSearchResponse = try await requestPath("/albums/\(albumId)/discover", method: "GET")
        return r.tracks
    }

    /// Spotify-Artist-Top-Tracks fuer Artist-Detail-Discover.
    func discoverArtistTracks(artistId: String) async throws -> [ExternalSearchResponse.Hit] {
        let r: ExternalSearchResponse = try await requestPath("/artists/\(artistId)/discover", method: "GET")
        return r.tracks
    }

    func myPlaylists() async throws -> [PlaylistSummary] {
        try await request("/playlists/me", method: "GET")
    }

    func createPlaylist(name: String, description: String? = nil, isPublic: Bool = false, isCollaborative: Bool = false) async throws -> PlaylistSummary {
        struct Body: Encodable { let name: String; let description: String?; let isPublic: Bool; let isCollaborative: Bool }
        return try await request("/playlists", method: "POST", body: Body(name: name, description: description, isPublic: isPublic, isCollaborative: isCollaborative))
    }

    func playlistDetail(id: String) async throws -> PlaylistDetail {
        try await request("/playlists/\(id)", method: "GET")
    }

    func deletePlaylist(id: String) async throws {
        try await requestVoid("/playlists/\(id)", method: "DELETE")
    }

    func addTracksToPlaylist(_ id: String, trackIds: [String]) async throws {
        struct Body: Encodable { let trackIds: [String] }
        let _: AddedResponse = try await request("/playlists/\(id)/tracks", method: "POST", body: Body(trackIds: trackIds))
    }

    func removeTrackFromPlaylist(_ id: String, trackId: String) async throws {
        try await requestVoid("/playlists/\(id)/tracks/\(trackId)", method: "DELETE")
    }

    func reorderPlaylist(_ id: String, moves: [(trackId: String, position: Int)]) async throws {
        struct Move: Encodable { let trackId: String; let position: Int }
        struct Body: Encodable { let moves: [Move] }
        let payload = Body(moves: moves.map { Move(trackId: $0.trackId, position: $0.position) })
        try await requestVoid("/playlists/\(id)/reorder", method: "PATCH", body: payload)
    }

    func albumDetail(id: String) async throws -> AlbumDetail {
        try await request("/albums/\(id)", method: "GET")
    }

    func artistDetail(id: String) async throws -> ArtistDetail {
        try await request("/artists/\(id)", method: "GET")
    }

    func scrapeJobs() async throws -> ScrapeJobsResponse {
        try await request("/admin/scrape/jobs", method: "GET")
    }

    func startScrape(playlistUrl: String) async throws -> ScrapeJob {
        struct Body: Encodable { let playlistUrl: String }
        return try await request("/admin/scrape", method: "POST", body: Body(playlistUrl: playlistUrl))
    }

    func cancelScrapeJob(id: String) async throws {
        try await requestVoid("/admin/scrape/jobs/\(id)", method: "DELETE")
    }

    /// Single-job status fuer polling (progress-bar wird daraus gespeist).
    func scrapeJob(id: String) async throws -> ScrapeJob {
        try await request("/admin/scrape/jobs/\(id)", method: "GET")
    }

    func pauseScrapeJob(id: String) async throws {
        struct Out: Decodable { let status: String }
        let _: Out = try await request("/admin/scrape/jobs/\(id)/pause", method: "POST")
    }

    func resumeScrapeJob(id: String) async throws {
        struct Out: Decodable { let status: String }
        let _: Out = try await request("/admin/scrape/jobs/\(id)/resume", method: "POST")
    }

    // MARK: Library — Liked Tracks / Saved Albums / Saved Artists

    struct LikedTracksResponse: Codable {
        struct Item: Codable, Identifiable, Hashable {
            let id: String
            let title: String
            let artist: String
            let artistId: String
            let album: String
            let albumId: String
            let coverUrl: String
            let durationMs: Int
        }
        let tracks: [Item]
    }

    func likedTracks() async throws -> [LikedTracksResponse.Item] {
        let r: LikedTracksResponse = try await request("/library/tracks", method: "GET")
        return r.tracks
    }

    func isTrackLiked(_ id: String) async throws -> Bool {
        struct Out: Decodable { let liked: Bool }
        let r: Out = try await request("/library/tracks/\(id)/status", method: "GET")
        return r.liked
    }

    func likeTrack(_ id: String) async throws {
        try await requestVoid("/library/tracks/\(id)", method: "POST")
    }

    func unlikeTrack(_ id: String) async throws {
        try await requestVoid("/library/tracks/\(id)", method: "DELETE")
    }

    struct SavedAlbumsResponse: Codable {
        struct Item: Codable, Identifiable, Hashable {
            let id: String
            let title: String
            let artist: String
            let artistId: String
            let coverUrl: String
            let releaseYear: Int
        }
        let albums: [Item]
    }

    func savedAlbums() async throws -> [SavedAlbumsResponse.Item] {
        let r: SavedAlbumsResponse = try await request("/library/albums", method: "GET")
        return r.albums
    }

    func isAlbumSaved(_ id: String) async throws -> Bool {
        struct Out: Decodable { let saved: Bool }
        let r: Out = try await request("/library/albums/\(id)/status", method: "GET")
        return r.saved
    }

    func saveAlbum(_ id: String) async throws {
        try await requestVoid("/library/albums/\(id)", method: "POST")
    }

    func unsaveAlbum(_ id: String) async throws {
        try await requestVoid("/library/albums/\(id)", method: "DELETE")
    }

    struct SavedArtistsResponse: Codable {
        struct Item: Codable, Identifiable, Hashable {
            let id: String
            let name: String
            let imageUrl: String?
        }
        let artists: [Item]
    }

    func savedArtists() async throws -> [SavedArtistsResponse.Item] {
        let r: SavedArtistsResponse = try await request("/library/artists", method: "GET")
        return r.artists
    }

    func isArtistSaved(_ id: String) async throws -> Bool {
        struct Out: Decodable { let saved: Bool }
        let r: Out = try await request("/library/artists/\(id)/status", method: "GET")
        return r.saved
    }

    func saveArtist(_ id: String) async throws {
        try await requestVoid("/library/artists/\(id)", method: "POST")
    }

    func unsaveArtist(_ id: String) async throws {
        try await requestVoid("/library/artists/\(id)", method: "DELETE")
    }

    // MARK: Mixed Playlist

    func generateMixedPlaylist() async throws -> PlaylistSummary {
        try await request("/browse/mixed", method: "POST")
    }

    // MARK: Collaborators

    func addCollaborator(playlistId: String, email: String, role: String = "EDITOR") async throws -> CollaboratorInfo {
        struct Body: Encodable { let email: String; let role: String }
        return try await request("/playlists/\(playlistId)/collaborators", method: "POST", body: Body(email: email, role: role))
    }

    func removeCollaborator(playlistId: String, userId: String) async throws {
        try await requestVoid("/playlists/\(playlistId)/collaborators/\(userId)", method: "DELETE")
    }

    // MARK: Jam

    struct JamCreateResponse: Codable {
        let code: String
        let sessionId: String
        let name: String?
        let hostUserId: String
    }

    struct JamJoinResponse: Codable {
        let code: String
        let sessionId: String
        let name: String?
        let hostUserId: String
        let hostDisplayName: String
        let currentTrackId: String?
        let positionMs: Int
        let isPaused: Bool
    }

    func createJam(name: String? = nil, trackId: String? = nil) async throws -> JamCreateResponse {
        struct Body: Encodable { let name: String?; let trackId: String? }
        return try await request("/jam", method: "POST", body: Body(name: name, trackId: trackId))
    }

    func joinJam(code: String) async throws -> JamJoinResponse {
        struct Body: Encodable { let code: String }
        return try await request("/jam/join", method: "POST", body: Body(code: code))
    }

    func leaveJam(code: String) async throws {
        try await requestVoid("/jam/\(code)/leave", method: "POST")
    }

    func endJam(code: String) async throws {
        try await requestVoid("/jam/\(code)", method: "DELETE")
    }

    // MARK: Lyrics (LRClib-Cache)

    struct LyricsResponse: Codable {
        let lrcSynced: String?
        let plain: String?
        let hasSync: Bool
        let source: String
    }

    func fetchLyrics(trackId: String) async throws -> LyricsResponse {
        try await request("/tracks/\(trackId)/lyrics", method: "GET")
    }

    // MARK: Dynamic Auto-Playlists

    struct DynamicSource: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let description: String?
        let coverUrl: String?
        let source: String
        let rotationMode: String
        let refreshIntervalH: Int
        let lastRefreshedAt: String?
        let trackCount: Int
        let enabled: Bool
    }

    struct DynamicSourcesResponse: Codable {
        let sources: [DynamicSource]
    }

    func dynamicSources() async throws -> [DynamicSource] {
        let r: DynamicSourcesResponse = try await request("/dynamic/sources", method: "GET")
        return r.sources
    }

    func toggleDynamicSource(source: String, enabled: Bool) async throws {
        struct Body: Encodable { let enabled: Bool }
        let encoded = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
        try await requestVoid("/dynamic/sources/\(encoded)/toggle", method: "POST", body: Body(enabled: enabled))
    }

    func updateDynamicSource(source: String, rotationMode: String? = nil, refreshIntervalH: Int? = nil) async throws {
        struct Body: Encodable { let rotationMode: String?; let refreshIntervalH: Int? }
        let encoded = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
        try await requestVoid("/dynamic/sources/\(encoded)", method: "PATCH",
                               body: Body(rotationMode: rotationMode, refreshIntervalH: refreshIntervalH))
    }

    // MARK: Offline-Download

    struct OfflineLicenseResponse: Codable {
        let trackId: String
        let downloadUrl: String
        let masterKeyHex: String
        let expiresAt: String
        let quotaUsed: Int
        let quotaTotal: Int
    }

    struct OfflineLicensesListResponse: Codable {
        struct Item: Codable, Identifiable, Hashable {
            let trackId: String
            let deviceId: String
            let expiresAt: String
            let issuedAt: String
            var id: String { trackId + "_" + deviceId }
        }
        let licenses: [Item]
        let quota: Int
    }

    func requestOfflineLicense(trackId: String) async throws -> OfflineLicenseResponse {
        struct Body: Encodable { let trackId: String; let deviceId: String }
        return try await request("/offline/licenses", method: "POST",
                                  body: Body(trackId: trackId, deviceId: deviceId))
    }

    func listOfflineLicenses() async throws -> OfflineLicensesListResponse {
        try await request("/offline/licenses?deviceId=\(deviceId)", method: "GET")
    }

    func revokeOfflineLicense(trackId: String) async throws {
        let encoded = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        try await requestVoid("/offline/licenses/\(trackId)?deviceId=\(encoded)", method: "DELETE")
    }

    // MARK: Request-raw helpers

    private struct AddedResponse: Decodable { let added: Int }

    /// Fuer DELETE / PATCH-no-body Endpoints (204 No Content)
    private func requestVoid(_ path: String, method: String, body: (any Encodable)? = nil) async throws {
        try await requestVoidPath(path, method: method, body: body, retried: false)
    }

    private func requestVoidPath(_ path: String, method: String, body: (any Encodable)?, retried: Bool) async throws {
        let url = try buildURL(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        guard let token = accessToken else { throw APIError.unauthorized }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.httpError(-1, "no response") }
        if http.statusCode == 401 && !retried {
            do { try await refresh() } catch {
                logout()
                throw APIError.unauthorized
            }
            try await requestVoidPath(path, method: method, body: body, retried: true)
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(http.statusCode, bodyStr.prefix(400).description)
        }
    }

    // MARK: Request-Core

    /// Alias fuer interne request-calls die bereits "/path?q=..." form haben.
    fileprivate func requestPath<T: Decodable>(_ path: String, method: String, body: (any Encodable)? = nil, auth: Bool = true) async throws -> T {
        try await request(path, method: method, body: body, auth: auth)
    }

    private func request<T: Decodable>(
        _ path: String, method: String, body: (any Encodable)? = nil, auth: Bool = true
    ) async throws -> T {
        try await requestInner(path, method: method, body: body, auth: auth, retried: false)
    }

    private func requestInner<T: Decodable>(
        _ path: String, method: String, body: (any Encodable)?, auth: Bool, retried: Bool
    ) async throws -> T {
        let url = try buildURL(path: path)
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
        if http.statusCode == 401 && auth && !retried {
            // Einmalig transparent refresh versuchen. `retried` verhindert infinite loop
            // falls der neue Access-Token auch sofort 401 gibt (z.B. widerrufen).
            do {
                try await refresh()
            } catch {
                // Refresh fehlgeschlagen → Tokens sind kaputt/widerrufen.
                // Auto-logout damit AppRoot zu LoginView switched statt 401-Loop.
                logout()
                throw APIError.unauthorized
            }
            return try await requestInner(path, method: method, body: body, auth: auth, retried: true)
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

    /// Baut URL aus baseURL + path. path kann "/foo" oder "/foo?a=b" sein. Wichtig: NICHT
    /// `appendingPathComponent` verwenden, das encoded `?` zu `%3F` und killt Query-Strings.
    private func buildURL(path: String) throws -> URL {
        let base = baseURL.absoluteString
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let prefixedPath = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: trimmedBase + prefixedPath) else {
            throw APIError.invalidURL
        }
        return url
    }
}

private struct AnyEncodable: Encodable {
    let wrapped: any Encodable
    init(_ w: any Encodable) { self.wrapped = w }
    func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
}
