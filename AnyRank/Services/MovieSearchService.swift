import Foundation

/// Result returned by a movie metadata lookup. Used to populate `RankItem`'s
/// Movies fields. `imdbURL` is constructed from the IMDB ID returned by TMDB.
struct MovieSearchResult: Identifiable, Equatable, Hashable, Sendable, Codable {
    let id: Int                  // TMDB ID
    let title: String
    let releaseYear: Int?
    let posterURL: URL?
    let imdbURL: URL?
}

protocol MovieSearchService: Sendable {
    func search(query: String) async throws -> [MovieSearchResult]
}
