import XCTest
@testable import AnyRank

/// TV shows (TMDB), including IMDb exports feeding a TV list.
@MainActor
final class TVCategoryTests: XCTestCase {

    private let imdbExport = """
    Const,Your Rating,Date Rated,Title,Title Type,Year
    tt0903747,10,2024-01-02,Breaking Bad,TV Series,2008
    tt5687612,9,2024-02-03,Fleabag,TV Mini Series,2016
    tt1375666,9,2024-03-04,Inception,Movie,2010
    tt0959621,8,2024-04-05,Pilot,TV Episode,2008
    """

    func test_imdbIntoTVList_keepsSeries_skipsFilmsAndEpisodes() throws {
        let candidates = try FileImporters.imdb(imdbExport, category: .tv)
        XCTAssertEqual(Set(candidates.map(\.item.name)), ["Breaking Bad", "Fleabag"])
        XCTAssertTrue(candidates.allSatisfy { $0.item.category == .tv })
        let breakingBad = try XCTUnwrap(candidates.first { $0.item.name == "Breaking Bad" })
        XCTAssertEqual(breakingBad.item.imdbID, "tt0903747")
        XCTAssertEqual(breakingBad.item.suggestedBucket, .loved)
    }

    func test_imdbIntoMoviesList_isUnchanged() throws {
        let candidates = try FileImporters.imdb(imdbExport)
        XCTAssertEqual(candidates.map(\.item.name), ["Inception"])
        XCTAssertTrue(candidates.allSatisfy { $0.item.category == .movies })
    }

    func test_imdbCanTargetMoviesOrTV_only() {
        XCTAssertTrue(ImportSourceKind.imdb.canTarget(.movies))
        XCTAssertTrue(ImportSourceKind.imdb.canTarget(.tv))
        XCTAssertFalse(ImportSourceKind.imdb.canTarget(.books))
        XCTAssertFalse(ImportSourceKind.letterboxd.canTarget(.tv))
    }

    func test_enricher_matchesImportedShow_byIMDbID() async {
        let enricher = ImportEnricher(
            movies: MockMovieSearchService(), tv: MockTVSearchService(), books: MockBookSearchService(),
            anime: MockAnimeSearchService(), games: MockGameSearchService(), music: MockMusicSearchService()
        )
        var imported = StagedItem(name: "Fleabag", category: .tv)
        imported.imdbID = "tt5687612"
        let enriched = await enricher.enrich(imported)
        XCTAssertEqual(enriched?.tv?.id, 67070)
        XCTAssertEqual(enriched?.tv?.seasonCount, 2)
    }

    func test_showRoundTripsThroughCSV() throws {
        let list = RankList(name: "TV", category: .tv)
        var staged = StagedItem(name: "The Wire", category: .tv)
        staged.tv = try XCTUnwrap(MockTVSearchService.pool.first { $0.title == "The Wire" })
        let item = RankItem(name: "The Wire", bucket: .loved, score: 10)
        staged.apply(to: item)
        list.items = [item]

        let decoded = RankList(name: "TV", category: .tv)
        try ListCSVCodec.decodeItems(into: decoded, from: ListCSVCodec.encodeItems(of: list))
        let round = try XCTUnwrap(decoded.items.first)
        round.list = decoded
        XCTAssertEqual(round.tmdbID, 1438)
        XCTAssertEqual(round.releaseYear, 2002)
        XCTAssertEqual(round.seasonCount, 5)
        XCTAssertEqual(round.primaryURL?.absoluteString, "https://www.imdb.com/title/tt0306414/")
        XCTAssertEqual(RankingApplier.comparisonSecondaryText(for: round, in: decoded), "2002 · 5 seasons")
        XCTAssertNotNil(RankingApplier.comparisonImageURLString(for: round, in: decoded))
    }
}
