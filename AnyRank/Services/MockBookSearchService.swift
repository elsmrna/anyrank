import Foundation

/// Canned-results implementation of `BookSearchService` used by previews,
/// snapshot tests, and the running app until a real book metadata source
/// is wired up. Query is a case-insensitive substring filter; empty query
/// returns the full pool so the picker is never empty.
struct MockBookSearchService: BookSearchService {

    var simulatedDelay: Duration = .zero

    func search(query: String) async throws -> [BookSearchResult] {
        if simulatedDelay > .zero {
            try? await Task.sleep(for: simulatedDelay)
        }
        guard !query.isEmpty else { return Self.pool }
        let lower = query.lowercased()
        let filtered = Self.pool.filter {
            $0.title.lowercased().contains(lower) || $0.author.lowercased().contains(lower)
        }
        return filtered.isEmpty ? Self.pool : filtered
    }

    private static let pool: [BookSearchResult] = [
        .init(
            id: "ol-1",
            title: "The Great Gatsby",
            author: "F. Scott Fitzgerald",
            publicationYear: 1925,
            isbn: "9780743273565",
            storyGraphURL: URL(string: "https://app.thestorygraph.com/books/the-great-gatsby"),
            coverURL: nil
        ),
        .init(
            id: "ol-2",
            title: "Mrs Dalloway",
            author: "Virginia Woolf",
            publicationYear: 1925,
            isbn: "9780156628709",
            storyGraphURL: URL(string: "https://app.thestorygraph.com/books/mrs-dalloway"),
            coverURL: nil
        ),
        .init(
            id: "ol-3",
            title: "Beloved",
            author: "Toni Morrison",
            publicationYear: 1987,
            isbn: "9781400033416",
            storyGraphURL: URL(string: "https://app.thestorygraph.com/books/beloved"),
            coverURL: nil
        ),
        .init(
            id: "ol-4",
            title: "A Brief History of Time",
            author: "Stephen Hawking",
            publicationYear: 1988,
            isbn: "9780553380163",
            storyGraphURL: URL(string: "https://app.thestorygraph.com/books/a-brief-history-of-time"),
            coverURL: nil
        ),
        .init(
            id: "ol-5",
            title: "Pachinko",
            author: "Min Jin Lee",
            publicationYear: 2017,
            isbn: "9781455563937",
            storyGraphURL: URL(string: "https://app.thestorygraph.com/books/pachinko"),
            coverURL: nil
        ),
        .init(
            id: "ol-6",
            title: "The Three-Body Problem",
            author: "Liu Cixin",
            publicationYear: 2008,
            isbn: "9780765382030",
            storyGraphURL: URL(string: "https://app.thestorygraph.com/books/the-three-body-problem"),
            coverURL: nil
        )
    ]
}
