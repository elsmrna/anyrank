import Foundation

/// Canned TV results for previews, tests, and when no TMDB token is set.
struct MockTVSearchService: TVSearchService {

    func searchShows(query: String) async throws -> [TVShowSearchResult] {
        guard !query.isEmpty else { return Self.pool }
        let lower = query.lowercased()
        let filtered = Self.pool.filter { $0.title.lowercased().contains(lower) }
        return filtered.isEmpty ? Self.pool : filtered
    }

    func lookupShow(imdbID: String) async throws -> TVShowSearchResult? {
        Self.pool.first { $0.imdbURL?.absoluteString.contains(imdbID) == true }
    }

    static let pool: [TVShowSearchResult] = [
        show(1438, "The Wire", 2002, 5, "/4lbclFySvugI51fwsyxBTOm4DqK.jpg", "tt0306414"),
        show(1396, "Breaking Bad", 2008, 5, "/anFx9aTOOYqgS3v7x3R84Kz67ly.jpg", "tt0903747"),
        show(67070, "Fleabag", 2016, 2, "/vFn0nLPcIggPH5LTWWaJ2hcsGlc.jpg", "tt5687612"),
        show(76331, "Succession", 2018, 4, "/z0XiwdrCQ9yVIr4O0pxzaAYRxdW.jpg", "tt7660850"),
        show(95396, "Severance", 2022, 3, "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg", "tt11280740"),
        show(136315, "The Bear", 2022, 5, "/eKfVzzEazSIjJMrw9ADa2x8ksLz.jpg", "tt14452776"),
    ]

    private static func show(_ id: Int, _ title: String, _ year: Int, _ seasons: Int, _ poster: String, _ imdb: String) -> TVShowSearchResult {
        TVShowSearchResult(
            id: id, title: title, firstAirYear: year, seasonCount: seasons,
            posterURL: URL(string: "https://image.tmdb.org/t/p/w342\(poster)"),
            imdbURL: URL(string: "https://www.imdb.com/title/\(imdb)/")
        )
    }
}
