import XCTest
@testable import AnyRank

/// Bands: Deezer artist search, display text, storage, and imports.
final class BandTests: XCTestCase {

    override func setUp() { ArtworkStubProtocol.reset() }
    override func tearDown() { ArtworkStubProtocol.reset() }

    private func service() -> LiveDeezerArtistService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArtworkStubProtocol.self]
        return LiveDeezerArtistService(session: URLSession(configuration: config))
    }

    func test_deezerSearch_decodesArtists() async throws {
        ArtworkStubProtocol.respond { _ in (200, Data("""
        {"data":[{"id":399,"name":"Radiohead","link":"https://www.deezer.com/artist/399",
          "picture_medium":"https://cdn-images.dzcdn.net/images/artist/x/250x250.jpg","nb_album":45,"nb_fan":4099428,"type":"artist"}],
         "total":1}
        """.utf8)) }

        let results = try await service().searchArtists(query: "radiohead")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, 399)
        XCTAssertEqual(results[0].fanCount, 4_099_428)
        XCTAssertEqual(results[0].deezerURL?.absoluteString, "https://www.deezer.com/artist/399")
        XCTAssertTrue(ArtworkStubProtocol.requested.first?.query?.contains("q=radiohead") ?? false)
    }

    func test_deezerErrorInA200Body_throws() async {
        ArtworkStubProtocol.respond { _ in (200, Data(#"{"error":{"type":"Exception","message":"Quota limit exceeded","code":4}}"#.utf8)) }
        do {
            _ = try await service().searchArtists(query: "radiohead")
            XCTFail("expected an error")
        } catch {}
    }

    func test_fanText() {
        XCTAssertEqual(ArtistText.fans(4_099_428), "4.1M fans")
        XCTAssertEqual(ArtistText.fans(446_905), "450K fans")
        XCTAssertEqual(ArtistText.fans(812), "810 fans")
        XCTAssertEqual(ArtistText.fans(1), "1 fan")
        XCTAssertNil(ArtistText.fans(nil))
    }

    @MainActor
    func test_bandRoundTripsThroughCSV() throws {
        let list = RankList(name: "Bands", category: .bands)
        var staged = StagedItem(name: "Talking Heads", category: .bands)
        staged.band = try XCTUnwrap(MockArtistSearchService.pool.first { $0.name == "Talking Heads" })
        let item = RankItem(name: "Talking Heads", bucket: .loved, score: 10)
        staged.apply(to: item)
        list.items = [item]

        let decoded = RankList(name: "Bands", category: .bands)
        try ListCSVCodec.decodeItems(into: decoded, from: ListCSVCodec.encodeItems(of: list))
        let round = try XCTUnwrap(decoded.items.first)
        round.list = decoded
        XCTAssertEqual(round.fanCount, 446_905)
        XCTAssertEqual(round.primaryURL?.absoluteString, "https://www.deezer.com/artist/181")
        XCTAssertNotNil(RankingApplier.comparisonImageURLString(for: round, in: decoded))
    }

    func test_enricher_fillsInPastedBand_byExactName() async {
        let enricher = ImportEnricher(
            movies: MockMovieSearchService(), books: MockBookSearchService(), anime: MockAnimeSearchService(),
            games: MockGameSearchService(), music: MockMusicSearchService(), bands: MockArtistSearchService()
        )
        let found = await enricher.enrich(StagedItem(name: "lcd soundsystem", category: .bands))
        XCTAssertEqual(found?.band?.id, 642)
        let missing = await enricher.enrich(StagedItem(name: "Not A Real Band", category: .bands))
        XCTAssertNil(missing)
    }
}
