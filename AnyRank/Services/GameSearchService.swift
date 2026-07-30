import Foundation

/// Result returned by a game metadata lookup. IGDB is the primary
/// source; `id` is IGDB's numeric ID. Cover URL uses IGDB's image CDN
/// at `t_cover_big` size (277×370, plenty for a comparison thumbnail).
struct GameSearchResult: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
    /// Platform abbreviations, in the order IGDB returned them
    /// (usually launch-platform first). Trimmed to a display-friendly
    /// short list — the UI further caps to ~3 with a "+N more" hint.
    let platforms: [String]
    let firstReleaseYear: Int?
    let coverURL: URL?
    let igdbURL: URL?
    let summary: String?
}

protocol GameSearchService: Sendable {
    func search(query: String) async throws -> [GameSearchResult]
}
