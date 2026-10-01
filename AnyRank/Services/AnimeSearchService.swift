import Foundation

/// Result returned by an anime metadata lookup. Title is the display
/// title (English preferred, romaji fallback); `alternateTitles` carries
/// the ones we didn't pick so item detail can show them.
///
/// `format` uses AniList's raw strings ("TV", "MOVIE", "OVA", "SPECIAL",
/// "ONA", "MUSIC") to avoid an enum migration when AniList adds new
/// formats. Display code lower-cases + prettifies for the UI.
struct AnimeSearchResult: Identifiable, Equatable, Hashable, Sendable, Codable {
    /// AniList `media.id`.
    let id: Int
    let title: String
    let alternateTitles: [String]
    let format: String?
    let seasonYear: Int?
    let episodeCount: Int?
    let coverURL: URL?
    let aniListURL: URL?
}

protocol AnimeSearchService: Sendable {
    func search(query: String) async throws -> [AnimeSearchResult]
}
