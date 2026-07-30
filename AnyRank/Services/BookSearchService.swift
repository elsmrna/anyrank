import Foundation

/// Result returned by a book metadata lookup. Used to populate `RankItem`'s
/// Books fields. `storyGraphURL` is what `RankItem.primaryURL` exposes for
/// the books category — it's the link the user tap-opens from the list.
///
/// StoryGraph URLs follow the pattern
/// `https://app.thestorygraph.com/books/<slug>` for known books and
/// `https://app.thestorygraph.com/browse?search_term=<query>` for search
/// fallbacks. Mock data uses the former; the live integration may need
/// the latter when an exact slug isn't recoverable from the upstream source.
struct BookSearchResult: Identifiable, Equatable, Hashable, Sendable {
    /// Stable identifier from whatever upstream source produced this result.
    /// For mocks this is a synthetic UUID-like string; for the live path
    /// it would be an OpenLibrary work key, ISBN, or similar.
    let id: String
    let title: String
    let author: String
    let publicationYear: Int?
    let isbn: String?
    let storyGraphURL: URL?
    /// Optional cover art URL. Open Library covers via
    /// `https://covers.openlibrary.org/b/id/<id>-L.jpg` — nil for books
    /// with no cover on file. Renders on the comparison screen and item
    /// detail; the app degrades gracefully to text when nil.
    let coverURL: URL?
}

protocol BookSearchService: Sendable {
    func search(query: String) async throws -> [BookSearchResult]
}
