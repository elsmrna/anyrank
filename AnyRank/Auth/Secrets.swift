import Foundation

/// Typed accessors for build-time secrets injected into Info.plist via
/// `Secrets.xcconfig`. Returns nil for keys that are unset or empty so the
/// app can degrade gracefully (e.g. local-only mode when OAuth isn't
/// configured yet).
enum Secrets {

    /// Google OAuth client ID for the iOS app. Pulled from Info.plist's
    /// `GIDClientID` key, which is populated at build time from the
    /// `GOOGLE_OAUTH_CLIENT_ID` xcconfig value. Returns nil if unset so
    /// sign-in can short-circuit with a clear error rather than crashing
    /// inside the SDK.
    static var googleOAuthClientID: String? {
        readNonEmpty("GIDClientID")
    }

    /// The reversed client ID used as a custom URL scheme by the Google
    /// Sign-In SDK to receive the OAuth redirect. Configured via
    /// `Secrets.xcconfig` and surfaced into Info.plist's CFBundleURLTypes.
    /// Reading it here is for diagnostics only — the SDK reads the URL
    /// scheme directly from Info.plist.
    static var googleOAuthReversedClientID: String? {
        readNonEmpty("GOOGLE_OAUTH_REVERSED_CLIENT_ID")
    }

    /// Google Places API key. Pulled from Info.plist's `GooglePlacesAPIKey`,
    /// populated at build time from the `GOOGLE_PLACES_API_KEY` xcconfig
    /// value. Returns nil if unset so the app can degrade to the mock
    /// search service rather than crashing inside the SDK. Note: the
    /// Places SDK is API-key gated, not OAuth-gated — the sign-in
    /// requirement we surface on the search screen is a UX gate, not a
    /// technical one.
    static var googlePlacesAPIKey: String? {
        readNonEmpty("GooglePlacesAPIKey")
    }

    /// TMDB (The Movie Database) API read access token. The long JWT-shaped
    /// bearer token from a TMDB developer account, not the shorter v3 API
    /// key. Populated from `TMDB_READ_TOKEN` xcconfig at build time.
    /// Returns nil when unset so `AnyRankApp` can fall back to
    /// `MockMovieSearchService` for dev/preview/test without a token.
    static var tmdbReadToken: String? {
        readNonEmpty("TMDBReadToken")
    }

    /// Twitch client ID + client secret. Twitch owns IGDB, and IGDB
    /// requires a Twitch client-credentials access token (no user
    /// interaction) plus the client ID as a header. Both values must
    /// be present for `LiveIGDBSearchService` to construct; either
    /// missing → mock fallback.
    static var twitchClientID: String? { readNonEmpty("TwitchClientID") }
    static var twitchClientSecret: String? { readNonEmpty("TwitchClientSecret") }

    /// Spotify client ID + client secret. Same client-credentials
    /// pattern as Twitch/IGDB — search-only usage doesn't require the
    /// user to sign in to Spotify. Missing either → mock fallback.
    static var spotifyClientID: String? { readNonEmpty("SpotifyClientID") }
    static var spotifyClientSecret: String? { readNonEmpty("SpotifyClientSecret") }

    /// Steam Web API key (https://steamcommunity.com/dev/apikey). Used to
    /// read a user's owned games for the Steam import. Missing → the import
    /// runs against a sample library.
    static var steamWebAPIKey: String? { readNonEmpty("SteamWebAPIKey") }

    private static func readNonEmpty(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
