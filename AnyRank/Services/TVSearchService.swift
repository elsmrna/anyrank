import Foundation

/// Result returned by a TV show lookup. Whole shows, not seasons.
struct TVShowSearchResult: Identifiable, Equatable, Hashable, Sendable, Codable {
    let id: Int                  // TMDB TV ID
    let title: String
    let firstAirYear: Int?
    let seasonCount: Int?
    let posterURL: URL?
    let imdbURL: URL?
}

protocol TVSearchService: Sendable {
    func searchShows(query: String) async throws -> [TVShowSearchResult]
    /// Exact lookup by IMDb ID (`tt…`). Nil when not found.
    func lookupShow(imdbID: String) async throws -> TVShowSearchResult?
}
