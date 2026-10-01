import Foundation

/// TMDB-backed implementation of `MovieSearchService`.
///
/// Uses the TMDB v3 REST API with a read access token (Bearer auth). Two
/// endpoints per search:
///
///   1. `GET /3/search/movie?query=…` — lightweight title search. Returns
///      TMDB IDs, titles, release dates, and poster paths.
///
///   2. `GET /3/movie/{id}/external_ids` — per-result IMDB ID lookup, so
///      each item can carry a direct IMDB link. This is the one bit of the
///      TMDB response that doesn't come back from `/search`. We fan these
///      out sequentially over the top few hits — TMDB's rate limits are
///      generous (~50 req/s) but sequential keeps the impl simple and
///      Sendable-clean under Swift 6.
///
/// Config: `Secrets.tmdbReadToken` must be populated. If it isn't,
/// `AnyRankApp` should be wiring `MockMovieSearchService` instead of this
/// type. The initializer throws when the token is missing so we fail fast
/// at construction rather than at first search.
struct LiveMovieSearchService: MovieSearchService {

    /// Cap on external-id lookups per search. The top 8 results cover
    /// every reasonable autocomplete UI; going deeper burns rate budget
    /// with no user-visible benefit.
    private static let detailFanoutLimit = 8

    private let readToken: String
    private let session: URLSession

    init(readToken: String, session: URLSession = .shared) {
        self.readToken = readToken
        self.session = session
    }

    /// Convenience initializer that pulls the token from `Secrets`. Fails
    /// if the token is missing — callers should check `Secrets.tmdbReadToken`
    /// first and fall back to the mock if nil.
    init?() {
        guard let token = Secrets.tmdbReadToken else { return nil }
        self.init(readToken: token)
    }

    func search(query: String) async throws -> [MovieSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let searchResults = try await tmdbSearch(query: trimmed)
        let topResults = Array(searchResults.prefix(Self.detailFanoutLimit))

        // Resolve IMDB IDs sequentially. Missing IMDB IDs are non-fatal —
        // the result still shows up, just without a link.
        var enriched: [MovieSearchResult] = []
        enriched.reserveCapacity(topResults.count)
        for hit in topResults {
            let imdbURL = try? await imdbURL(forMovieID: hit.id)
            enriched.append(
                MovieSearchResult(
                    id: hit.id,
                    title: hit.title,
                    releaseYear: hit.releaseYear,
                    posterURL: hit.posterURL,
                    imdbURL: imdbURL
                )
            )
        }
        return enriched
    }

    /// `GET /3/find/{imdb_id}?external_source=imdb_id` — one call, exact
    /// match. Used by imports that already know the IMDb ID.
    func lookup(imdbID: String) async throws -> MovieSearchResult? {
        var components = URLComponents(string: "https://api.themoviedb.org/3/find/\(imdbID)")!
        components.queryItems = [URLQueryItem(name: "external_source", value: "imdb_id")]
        guard let url = components.url else { return nil }
        let data = try await get(url: url)
        let decoded = try JSONDecoder().decode(TMDBFindResponse.self, from: data)
        guard let raw = decoded.movie_results.first else { return nil }
        return MovieSearchResult(
            id: raw.id,
            title: raw.title,
            releaseYear: raw.release_date.flatMap { Self.year(from: $0) },
            posterURL: raw.poster_path.flatMap { Self.posterURL(fromPath: $0) },
            imdbURL: URL(string: "https://www.imdb.com/title/\(imdbID)/")
        )
    }

    // MARK: - TMDB endpoints

    private func tmdbSearch(query: String) async throws -> [MovieSearchResult] {
        var components = URLComponents(string: "https://api.themoviedb.org/3/search/movie")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        guard let url = components.url else { return [] }

        let data = try await get(url: url)
        let decoded = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)

        return decoded.results.map { raw in
            MovieSearchResult(
                id: raw.id,
                title: raw.title,
                releaseYear: raw.release_date.flatMap { Self.year(from: $0) },
                posterURL: raw.poster_path.flatMap { Self.posterURL(fromPath: $0) },
                imdbURL: nil
            )
        }
    }

    private func imdbURL(forMovieID id: Int) async throws -> URL? {
        let url = URL(string: "https://api.themoviedb.org/3/movie/\(id)/external_ids")!
        let data = try await get(url: url)
        let decoded = try JSONDecoder().decode(TMDBExternalIDs.self, from: data)
        guard let imdbID = decoded.imdb_id, !imdbID.isEmpty else { return nil }
        return URL(string: "https://www.imdb.com/title/\(imdbID)/")
    }

    // MARK: - HTTP

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(readToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveServiceError.notImplemented("TMDB HTTP \(http.statusCode)")
        }
        return data
    }

    // MARK: - Helpers

    /// Poster URL uses TMDB's image CDN at a moderate width — enough for
    /// list rows and detail thumbnails, small enough not to blow the
    /// network budget on typeahead. `w342` is the standard "medium" tier.
    private static func posterURL(fromPath path: String) -> URL? {
        URL(string: "https://image.tmdb.org/t/p/w342\(path)")
    }

    /// TMDB returns release dates as `YYYY-MM-DD`. We only want the year.
    private static func year(from releaseDate: String) -> Int? {
        Int(releaseDate.prefix(4))
    }
}

// MARK: - Wire formats

/// Minimal TMDB `/search/movie` response shape — only the fields we use.
private struct TMDBSearchResponse: Decodable {
    let results: [Raw]

    struct Raw: Decodable {
        let id: Int
        let title: String
        let release_date: String?
        let poster_path: String?
    }
}

/// Minimal TMDB `/find/{external_id}` response shape.
private struct TMDBFindResponse: Decodable {
    let movie_results: [TMDBSearchResponse.Raw]
}

/// Minimal TMDB `/movie/{id}/external_ids` response shape.
private struct TMDBExternalIDs: Decodable {
    let imdb_id: String?
}
