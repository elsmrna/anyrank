import Foundation

/// Spotify-backed implementation of `MusicSearchService`.
///
/// Spotify's Web API supports two auth flows: user-facing OAuth (needed
/// only for calls that act on a user's account, like playlists) and
/// app-level client credentials for catalog reads (what we need here).
/// We use client credentials via `AppOAuthTokenStore` — same helper as
/// IGDB — so search doesn't add any user consent burden.
///
/// Endpoints:
///   - `GET /v1/search?type=album` for `searchAlbums`
///   - `GET /v1/search?type=track` for `searchSongs`
///
/// `init?()` returns nil when either `SPOTIFY_CLIENT_ID` or
/// `SPOTIFY_CLIENT_SECRET` is missing — `AnyRankApp` falls back to
/// the mock in that case.
final class LiveSpotifyMusicService: MusicSearchService, @unchecked Sendable {

    private static let searchEndpoint = URL(string: "https://api.spotify.com/v1/search")!
    private static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!
    private static let resultLimit = 15

    private let session: URLSession
    private let tokenStore: AppOAuthTokenStore

    init?(session: URLSession = .shared) {
        guard let id = Secrets.spotifyClientID, let secret = Secrets.spotifyClientSecret else {
            return nil
        }
        self.session = session
        self.tokenStore = AppOAuthTokenStore(refresher: {
            try await Self.fetchAppAccessToken(clientID: id, clientSecret: secret, session: session)
        })
    }

    func searchAlbums(query: String) async throws -> [AlbumSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let data = try await search(query: trimmed, type: "album")
        let decoded = try JSONDecoder().decode(SearchAlbumsResponse.self, from: data)
        return decoded.albums.items.map { a in
            AlbumSearchResult(
                id: a.id,
                title: a.name,
                artist: (a.artists ?? []).map(\.name).joined(separator: ", "),
                releaseYear: Self.year(from: a.release_date),
                coverURL: (a.images ?? []).first.flatMap { URL(string: $0.url) },
                spotifyURL: a.external_urls?.spotify.flatMap { URL(string: $0) }
            )
        }
    }

    func searchSongs(query: String) async throws -> [SongSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let data = try await search(query: trimmed, type: "track")
        let decoded = try JSONDecoder().decode(SearchTracksResponse.self, from: data)
        return decoded.tracks.items.map { t in
            SongSearchResult(
                id: t.id,
                title: t.name,
                artist: (t.artists ?? []).map(\.name).joined(separator: ", "),
                albumTitle: t.album?.name,
                releaseYear: Self.year(from: t.album?.release_date),
                durationSeconds: t.duration_ms.map { $0 / 1000 },
                coverURL: (t.album?.images ?? []).first.flatMap { URL(string: $0.url) },
                spotifyURL: t.external_urls?.spotify.flatMap { URL(string: $0) }
            )
        }
    }

    // MARK: - HTTP

    private func search(query: String, type: String) async throws -> Data {
        let token = try await tokenStore.currentToken()

        var components = URLComponents(url: Self.searchEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "limit", value: "\(Self.resultLimit)")
        ]
        guard let url = components.url else { return Data() }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveServiceError.notImplemented("Spotify HTTP \(http.statusCode)")
        }
        return data
    }

    // MARK: - Token refresh

    private static func fetchAppAccessToken(
        clientID: String,
        clientSecret: String,
        session: URLSession
    ) async throws -> AppOAuthTokenStore.Token {
        // Spotify's client-credentials token endpoint expects a
        // form-encoded body and a Basic Auth header built from
        // `<client_id>:<client_secret>`.
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        let basic = "\(clientID):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveServiceError.notImplemented("Spotify OAuth HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        return .init(
            value: decoded.access_token,
            expiresAt: Date(timeIntervalSinceNow: TimeInterval(decoded.expires_in))
        )
    }

    // MARK: - Helpers

    /// Spotify's `release_date` can be `"YYYY"`, `"YYYY-MM"`, or
    /// `"YYYY-MM-DD"` depending on `release_date_precision`. Take the
    /// first four chars regardless.
    private static func year(from raw: String?) -> Int? {
        guard let raw, raw.count >= 4 else { return nil }
        return Int(raw.prefix(4))
    }
}

// MARK: - Wire format

private struct SpotifyTokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
}

private struct SearchAlbumsResponse: Decodable {
    let albums: AlbumPage
    struct AlbumPage: Decodable { let items: [SpotifyAlbum] }
}

private struct SearchTracksResponse: Decodable {
    let tracks: TrackPage
    struct TrackPage: Decodable { let items: [SpotifyTrack] }
}

private struct SpotifyAlbum: Decodable {
    let id: String
    let name: String
    let release_date: String?
    let artists: [SpotifyArtist]?
    let images: [SpotifyImage]?
    let external_urls: ExternalURLs?
}

private struct SpotifyTrack: Decodable {
    let id: String
    let name: String
    let duration_ms: Int?
    let artists: [SpotifyArtist]?
    let album: SpotifyAlbum?
    let external_urls: ExternalURLs?
}

private struct SpotifyArtist: Decodable {
    let name: String
}

private struct SpotifyImage: Decodable {
    let url: String
}

private struct ExternalURLs: Decodable {
    let spotify: String?
}
