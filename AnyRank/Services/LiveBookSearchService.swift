import Foundation

/// Open Library-backed implementation of `BookSearchService`.
///
/// StoryGraph doesn't publish a public read API, so the integration
/// shape is:
///
///   1. Search Open Library's `/search.json` endpoint for title, author,
///      year, ISBN, and cover ID. Open Library is free, keyless, and has
///      generous rate limits for non-commercial use.
///   2. Construct the StoryGraph URL from the result. Prefer a slug URL
///      built from the title (works ~80% of the time); fall back to
///      StoryGraph's browse-search URL when the slug would 404. See
///      `issues/closed/live-storygraph.md` for the tradeoff rationale.
///   3. Cover images come from `https://covers.openlibrary.org/b/id/…-L.jpg`.
///
/// No API key is required. `AnyRankApp` can wire this directly with no
/// configuration guard; the mock stays available for previews and tests
/// via environment injection.
struct LiveBookSearchService: BookSearchService {

    /// How many search hits to keep. Open Library returns 20+ per query
    /// by default; 15 is plenty for a typeahead-style picker.
    private static let resultLimit = 15

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String) async throws -> [BookSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,isbn,cover_i"),
            URLQueryItem(name: "limit", value: "\(Self.resultLimit)")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveServiceError.notImplemented("Open Library HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(OpenLibrarySearchResponse.self, from: data)

        return decoded.docs.compactMap { doc in
            guard let title = doc.title else { return nil }
            let author = doc.author_name?.first ?? "Unknown"
            let isbn = doc.isbn?.first
            let coverURL = doc.cover_i.flatMap {
                URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg")
            }
            let storyGraphURL = Self.storyGraphURL(forTitle: title)

            return BookSearchResult(
                id: doc.key ?? UUID().uuidString,
                title: title,
                author: author,
                publicationYear: doc.first_publish_year,
                isbn: isbn,
                storyGraphURL: storyGraphURL,
                coverURL: coverURL
            )
        }
    }

    // MARK: - StoryGraph URL

    /// Optimistic slug URL. StoryGraph slugs are almost always the title
    /// lowercased with punctuation stripped and spaces hyphenated. Works
    /// ~80% of the time; when it 404s, the user still lands on
    /// StoryGraph's site where the built-in search can rescue them.
    ///
    /// If the resulting slug is empty (title was all punctuation, e.g.),
    /// fall back to StoryGraph's browse URL keyed on the raw title.
    private static func storyGraphURL(forTitle title: String) -> URL? {
        let slug = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "-")

        if !slug.isEmpty {
            return URL(string: "https://app.thestorygraph.com/books/\(slug)")
        }

        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://app.thestorygraph.com/browse?search_term=\(encoded)")
    }
}

// MARK: - Wire format

/// Minimal Open Library `/search.json` response shape — only the fields
/// we ask for via the `fields=` query parameter.
private struct OpenLibrarySearchResponse: Decodable {
    let docs: [Doc]

    struct Doc: Decodable {
        let key: String?
        let title: String?
        let author_name: [String]?
        let first_publish_year: Int?
        let isbn: [String]?
        let cover_i: Int?
    }
}
