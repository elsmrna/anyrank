import Foundation

/// Result for a single album lookup. `id` is a Spotify album id (base62
/// string) when live, or a synthetic string for mocks. `coverURL` uses
/// Spotify's images at a moderate size (~300px).
struct AlbumSearchResult: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let releaseYear: Int?
    let coverURL: URL?
    let spotifyURL: URL?
}

/// Result for a single song lookup. Songs carry their parent album
/// title too — helpful for disambiguating covers and re-releases.
struct SongSearchResult: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumTitle: String?
    let releaseYear: Int?
    let durationSeconds: Int?
    let coverURL: URL?
    let spotifyURL: URL?
}

/// Single protocol for both music categories — the two methods share
/// auth, rate-limit budget, and (in the live implementation) token
/// refresh. `Category.albums` and `Category.songs` each dispatch to
/// their matching method.
protocol MusicSearchService: Sendable {
    func searchAlbums(query: String) async throws -> [AlbumSearchResult]
    func searchSongs(query: String) async throws -> [SongSearchResult]
}
