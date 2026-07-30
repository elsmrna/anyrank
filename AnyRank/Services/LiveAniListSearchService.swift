import Foundation

/// AniList-backed implementation of `AnimeSearchService`.
///
/// AniList's GraphQL API doesn't require authentication for search
/// queries, so this service has no `Secrets.xcconfig` entry and can be
/// injected unconditionally. Rate limit is 90 req/min per IP — the
/// standard 250ms typeahead debounce in `AnimeSearchScreen` stays well
/// under that ceiling.
///
/// One fixed GraphQL query per search — hand-written string, no
/// GraphQL client library. The response is `Codable`-decoded.
struct LiveAniListSearchService: AnimeSearchService {

    private static let endpoint = URL(string: "https://graphql.anilist.co")!

    /// Cap on returned hits. AniList's `perPage` is 1-50 for anonymous
    /// callers; 15 comfortably covers the typeahead picker.
    private static let resultLimit = 15

    private static let query = """
    query ($search: String) {
      Page(perPage: \(resultLimit)) {
        media(search: $search, type: ANIME, sort: [SEARCH_MATCH, POPULARITY_DESC]) {
          id
          title { english romaji native }
          format
          seasonYear
          episodes
          coverImage { large }
          siteUrl
        }
      }
    }
    """

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String) async throws -> [AnimeSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = GraphQLRequest(query: Self.query, variables: .init(search: trimmed))
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveServiceError.notImplemented("AniList HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        return decoded.data.Page.media.map { m in
            let (display, alternates) = Self.pickTitles(from: m.title)
            return AnimeSearchResult(
                id: m.id,
                title: display,
                alternateTitles: alternates,
                format: m.format,
                seasonYear: m.seasonYear,
                episodeCount: m.episodes,
                coverURL: m.coverImage?.large.flatMap { URL(string: $0) },
                aniListURL: m.siteUrl.flatMap { URL(string: $0) }
            )
        }
    }

    /// English preferred, romaji fallback, native as a last resort. The
    /// two not-picked variants become `alternateTitles` for item detail.
    private static func pickTitles(from title: Title) -> (display: String, alternates: [String]) {
        let english = title.english?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let romaji  = title.romaji?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let native  = title.native?.trimmingCharacters(in: .whitespaces).nilIfEmpty

        if let english {
            return (english, [romaji, native].compactMap { $0 })
        } else if let romaji {
            return (romaji, [native].compactMap { $0 })
        } else {
            return (native ?? "Untitled", [])
        }
    }
}

// MARK: - Wire format

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: Variables
    struct Variables: Encodable {
        let search: String
    }
}

private struct GraphQLResponse: Decodable {
    let data: DataBlock
    struct DataBlock: Decodable {
        let Page: PageBlock
    }
    struct PageBlock: Decodable {
        let media: [Media]
    }
    struct Media: Decodable {
        let id: Int
        let title: Title
        let format: String?
        let seasonYear: Int?
        let episodes: Int?
        let coverImage: CoverImage?
        let siteUrl: String?
    }
    struct CoverImage: Decodable {
        let large: String?
    }
}

private struct Title: Decodable {
    let english: String?
    let romaji: String?
    let native: String?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
