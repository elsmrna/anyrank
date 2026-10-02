import Foundation

/// Result for a single album lookup. `id` is a Spotify album id (base62
/// string) when live, or a synthetic string for mocks. `coverURL` uses
/// Spotify's images at a moderate size (~300px).
struct AlbumSearchResult: Identifiable, Equatable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let artist: String
    let releaseYear: Int?
    let coverURL: URL?
    let spotifyURL: URL?
}

/// Album search for `Category.albums`.
protocol MusicSearchService: Sendable {
    func searchAlbums(query: String) async throws -> [AlbumSearchResult]
}
