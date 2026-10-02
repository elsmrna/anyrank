import XCTest
@testable import AnyRank

/// Manga (AniList) and Stays (Google Places lodging).
@MainActor
final class NewCategoriesTests: XCTestCase {

    func test_mangaItem_roundTripsThroughCSV() throws {
        let list = RankList(name: "Manga", category: .manga)
        var staged = StagedItem(name: "Monster", category: .manga)
        staged.manga = try XCTUnwrap(MockMangaSearchService.pool.first { $0.title == "Monster" })
        let item = RankItem(name: "Monster", bucket: .loved, score: 10)
        staged.apply(to: item)
        list.items = [item]

        let decoded = RankList(name: "Manga", category: .manga)
        try ListCSVCodec.decodeItems(into: decoded, from: ListCSVCodec.encodeItems(of: list))
        let round = try XCTUnwrap(decoded.items.first)
        XCTAssertEqual(round.animeFormat, "Manga")
        XCTAssertEqual(round.releaseYear, 1994)
        XCTAssertEqual(round.chapterCount, 162)
        XCTAssertEqual(round.volumeCount, 18)
        XCTAssertEqual(round.aniListURLString, "https://anilist.co/manga/30001")
        XCTAssertNotNil(round.coverURLString)
        round.list = decoded
        XCTAssertEqual(round.primaryURL?.absoluteString, "https://anilist.co/manga/30001")
        XCTAssertEqual(RankingApplier.comparisonSecondaryText(for: round, in: decoded), "1994 · 18 vols")
    }

    func test_stayItem_isAPlace_withMapAndLodgingSearch() throws {
        let list = RankList(name: "Stays", category: .stays)
        XCTAssertTrue(list.isPlaceList, "stays get the map view")
        XCTAssertEqual(list.placesSearchKind, .lodging)
        XCTAssertFalse(Category.stays.hasArtwork)

        var staged = StagedItem(name: "Hotel Figueroa", category: .stays)
        staged.place = try XCTUnwrap(MockPlacesSearchService.lodgingPool.first { $0.name == "Hotel Figueroa" })
        let item = RankItem(name: "Hotel Figueroa", bucket: .loved)
        staged.apply(to: item)
        item.list = list
        XCTAssertNotNil(item.latitude)
        XCTAssertEqual(item.primaryURL?.host, "maps.google.com")
        XCTAssertEqual(staged.secondaryText, "939 S Figueroa St, Los Angeles, CA")
    }

    func test_mockPlaces_lodgingSearch_returnsHotels() async throws {
        let results = try await MockPlacesSearchService().search(query: "", kind: .lodging)
        XCTAssertTrue(results.contains { $0.name == "Chateau Marmont" })
        XCTAssertFalse(results.contains { $0.name == "Bestia" })
    }

    func test_mangaFormat_display() {
        XCTAssertEqual(MangaFormat.display("MANGA"), "Manga")
        XCTAssertEqual(MangaFormat.display("MANGA", countryOfOrigin: "KR"), "Manhwa")
        XCTAssertEqual(MangaFormat.display("MANGA", countryOfOrigin: "CN"), "Manhua")
        XCTAssertEqual(MangaFormat.display("NOVEL"), "Light novel")
        XCTAssertEqual(MangaFormat.display("ONE_SHOT"), "One-shot")
        XCTAssertNil(MangaFormat.display(nil))
    }

    func test_mangaLength_prefersVolumes_thenChapters() {
        XCTAssertEqual(MangaLength.text(chapters: 327, volumes: 37), "37 vols")
        XCTAssertEqual(MangaLength.text(chapters: 147, volumes: nil), "147 ch")
        XCTAssertNil(MangaLength.text(chapters: nil, volumes: nil), "ongoing series show no length")
        XCTAssertEqual(MangaLength.text(chapters: nil, volumes: 1, long: true), "1 volume")
    }

    func test_importEnricher_fillsInPastedManga_byExactTitle() async throws {
        let enricher = ImportEnricher(
            movies: MockMovieSearchService(), books: MockBookSearchService(), anime: MockAnimeSearchService(),
            manga: MockMangaSearchService(), games: MockGameSearchService(), music: MockMusicSearchService()
        )
        let pasted = StagedItem(name: "goodnight punpun", category: .manga)
        let found = await enricher.enrich(pasted)
        XCTAssertEqual(found?.manga?.id, 34632)
        let missing = await enricher.enrich(StagedItem(name: "Not A Real Manga", category: .manga))
        XCTAssertNil(missing)
    }

    func test_pluralNouns() {
        XCTAssertEqual(Category.manga.pluralNoun, "manga")
        XCTAssertEqual(Category.anime.pluralNoun, "anime")
        XCTAssertEqual(Category.stays.pluralNoun, "stays")
        XCTAssertEqual(Category.custom.pluralNoun, "items")
    }
}
