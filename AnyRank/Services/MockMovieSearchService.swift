import Foundation

/// Canned-results implementation of `MovieSearchService` used by previews,
/// snapshot tests, and (for now) the running app until a TMDB API key is wired up.
struct MockMovieSearchService: MovieSearchService {

    var simulatedDelay: Duration = .zero

    func search(query: String) async throws -> [MovieSearchResult] {
        if simulatedDelay > .zero {
            try? await Task.sleep(for: simulatedDelay)
        }
        guard !query.isEmpty else { return Self.pool }
        let lower = query.lowercased()
        let filtered = Self.pool.filter { $0.title.lowercased().contains(lower) }
        return filtered.isEmpty ? Self.pool : filtered
    }

    private static let pool: [MovieSearchResult] = [
        .init(
            id: 27205,
            title: "Inception",
            releaseYear: 2010,
            posterURL: nil,
            imdbURL: URL(string: "https://www.imdb.com/title/tt1375666/")
        ),
        .init(
            id: 155,
            title: "The Dark Knight",
            releaseYear: 2008,
            posterURL: nil,
            imdbURL: URL(string: "https://www.imdb.com/title/tt0468569/")
        ),
        .init(
            id: 105,
            title: "Back to the Future",
            releaseYear: 1985,
            posterURL: nil,
            imdbURL: URL(string: "https://www.imdb.com/title/tt0088763/")
        ),
        .init(
            id: 680,
            title: "Pulp Fiction",
            releaseYear: 1994,
            posterURL: nil,
            imdbURL: URL(string: "https://www.imdb.com/title/tt0110912/")
        ),
        .init(
            id: 13,
            title: "Forrest Gump",
            releaseYear: 1994,
            posterURL: nil,
            imdbURL: URL(string: "https://www.imdb.com/title/tt0109830/")
        )
    ]
}
