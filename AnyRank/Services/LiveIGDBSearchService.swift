import Foundation

/// IGDB-backed implementation of `GameSearchService`.
///
/// IGDB is Twitch-owned and uses Twitch's OAuth 2.0 client-credentials
/// flow. The app exchanges `TWITCH_CLIENT_ID` + `TWITCH_CLIENT_SECRET`
/// for a short-lived bearer token, which is passed alongside the
/// client ID to `api.igdb.com`. The token refresh is handled by
/// `AppOAuthTokenStore`.
///
/// Query language is IGDB's custom "Apicalypse" — a POST body of
/// `search "..."; fields ...; limit N;`. No client library needed;
/// hand-formatted string is enough.
///
/// `LiveIGDBSearchService.init?()` returns nil when either secret is
/// missing so `AnyRankApp` can fall back to the mock without crashing.
final class LiveIGDBSearchService: GameSearchService, @unchecked Sendable {

    private static let endpoint = URL(string: "https://api.igdb.com/v4/games")!
    private static let tokenEndpoint = URL(string: "https://id.twitch.tv/oauth2/token")!
    private static let resultLimit = 15

    private let clientID: String
    private let session: URLSession
    private let tokenStore: AppOAuthTokenStore

    init?(session: URLSession = .shared) {
        guard let id = Secrets.twitchClientID, let secret = Secrets.twitchClientSecret else {
            return nil
        }
        self.clientID = id
        self.session = session

        // The refresher captures the secret; the store hangs onto the
        // resulting token until it's within 60s of expiry.
        self.tokenStore = AppOAuthTokenStore(refresher: {
            try await Self.fetchAppAccessToken(clientID: id, clientSecret: secret, session: session)
        })
    }

    func search(query: String) async throws -> [GameSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let token = try await tokenStore.currentToken()

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Apicalypse body. Escape quotes in the search term defensively.
        let safe = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
        let body = """
        search "\(safe)"; fields name,first_release_date,cover.image_id,platforms.abbreviation,url,summary; limit \(Self.resultLimit);
        """
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveServiceError.notImplemented("IGDB HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode([IGDBGame].self, from: data)
        return decoded.map { g in
            GameSearchResult(
                id: g.id,
                name: g.name ?? "Untitled",
                platforms: (g.platforms ?? []).compactMap(\.abbreviation),
                firstReleaseYear: g.first_release_date.flatMap { Self.year(from: $0) },
                coverURL: g.cover?.image_id.flatMap { Self.coverURL(from: $0) },
                igdbURL: g.url.flatMap { URL(string: $0) },
                summary: g.summary
            )
        }
    }

    // MARK: - Token refresh

    private static func fetchAppAccessToken(
        clientID: String,
        clientSecret: String,
        session: URLSession
    ) async throws -> AppOAuthTokenStore.Token {
        var components = URLComponents(url: tokenEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "grant_type", value: "client_credentials")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveServiceError.notImplemented("Twitch OAuth HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(TwitchTokenResponse.self, from: data)
        return .init(
            value: decoded.access_token,
            expiresAt: Date(timeIntervalSinceNow: TimeInterval(decoded.expires_in))
        )
    }

    // MARK: - Helpers

    private static func coverURL(from imageID: String) -> URL? {
        URL(string: "https://images.igdb.com/igdb/image/upload/t_cover_big/\(imageID).jpg")
    }

    private static func year(from unixSeconds: Int) -> Int? {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        return Calendar(identifier: .gregorian).dateComponents([.year], from: date).year
    }
}

// MARK: - Wire format

private struct TwitchTokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
}

private struct IGDBGame: Decodable {
    let id: Int
    let name: String?
    let first_release_date: Int?
    let cover: IGDBCover?
    let platforms: [IGDBPlatform]?
    let url: String?
    let summary: String?
}

private struct IGDBCover: Decodable {
    let image_id: String?
}

private struct IGDBPlatform: Decodable {
    let abbreviation: String?
}
