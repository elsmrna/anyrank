import Foundation

/// Small in-memory cache for app-level OAuth 2.0 client-credentials
/// bearer tokens. IGDB (via Twitch) and Spotify both mint short-lived
/// tokens from a `(client_id, client_secret)` pair without any user
/// interaction; this actor holds the current token and refreshes it
/// when it's within `expiryMargin` of expiry.
///
/// Not persisted — one token per app launch is fine given the ~60-day
/// (Twitch) / ~1-hour (Spotify) lifetimes and the app's typical
/// session length. Persisting to Keychain is a small future win but
/// not necessary today.
///
/// Concurrency: an actor so multiple concurrent search calls can
/// safely `await currentToken(refresh:)` without duplicating the
/// refresh work.
actor AppOAuthTokenStore {

    struct Token {
        let value: String
        let expiresAt: Date
    }

    /// A refresh strategy — supplied by the caller (Twitch, Spotify, …)
    /// so this store stays provider-agnostic. Returns a fresh token
    /// with its expiry.
    typealias Refresher = @Sendable () async throws -> Token

    /// Leave this much slack before the recorded expiry — a 60-second
    /// margin comfortably covers both clock skew and requests that
    /// take a few seconds to complete.
    private static let expiryMargin: TimeInterval = 60

    private var cached: Token?
    private let refresher: Refresher

    init(refresher: @escaping Refresher) {
        self.refresher = refresher
    }

    /// Returns a valid token — reuses the cached one when it's still
    /// good, otherwise refreshes. All callers converge on the same
    /// refresh call because the actor serializes them.
    func currentToken() async throws -> String {
        if let cached, cached.expiresAt.timeIntervalSinceNow > Self.expiryMargin {
            return cached.value
        }
        let fresh = try await refresher()
        cached = fresh
        return fresh.value
    }
}
