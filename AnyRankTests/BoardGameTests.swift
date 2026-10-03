import XCTest
@testable import AnyRank

/// Board games: the BoardGameGeek XML client (against canned responses in
/// BGG's documented format), display text, and storage.
final class BoardGameTests: XCTestCase {

    private let searchXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <items total="3" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
      <item type="boardgame" id="9999"><name type="primary" value="Catan: Junior"/><yearpublished value="2011"/></item>
      <item type="boardgame" id="13"><name type="primary" value="CATAN"/><yearpublished value="1995"/></item>
      <item type="boardgame" id="27710"><name type="primary" value="Catan Dice Game"/><yearpublished value="2007"/></item>
    </items>
    """

    private let thingXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <items termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
      <item type="boardgame" id="9999">
        <thumbnail>https://cf.geekdo-images.com/junior.jpg</thumbnail>
        <name type="primary" sortindex="1" value="Catan: Junior"/>
        <yearpublished value="2011"/><minplayers value="2"/><maxplayers value="4"/><playingtime value="30"/>
        <statistics page="1"><ratings><usersrated value="4000"/></ratings></statistics>
      </item>
      <item type="boardgame" id="13">
        <thumbnail>//cf.geekdo-images.com/catan.jpg</thumbnail>
        <name type="primary" sortindex="1" value="CATAN"/>
        <name type="alternate" sortindex="1" value="Die Siedler von Catan"/>
        <yearpublished value="1995"/><minplayers value="3"/><maxplayers value="4"/><playingtime value="120"/>
        <statistics page="1"><ratings><usersrated value="120000"/></ratings></statistics>
      </item>
      <item type="boardgame" id="27710">
        <name type="primary" sortindex="1" value="Catan Dice Game"/>
        <yearpublished value="2007"/><minplayers value="1"/><maxplayers value="4"/><playingtime value="0"/>
        <statistics page="1"><ratings><usersrated value="9000"/></ratings></statistics>
      </item>
    </items>
    """

    override func setUp() { ArtworkStubProtocol.reset() }
    override func tearDown() { ArtworkStubProtocol.reset() }

    func test_search_sendsToken_parsesDetails_andPutsExactThenPopularFirst() async throws {
        ArtworkStubProtocol.respond { [searchXML, thingXML] url in
            url.path.hasSuffix("/search") ? (200, Data(searchXML.utf8)) : (200, Data(thingXML.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArtworkStubProtocol.self]
        let service = LiveBGGSearchService(token: "test-token", session: URLSession(configuration: config))

        let results = try await service.searchBoardGames(query: "Catan")

        XCTAssertEqual(results.map(\.name), ["CATAN", "Catan Dice Game", "Catan: Junior"])
        let catan = try XCTUnwrap(results.first)
        XCTAssertEqual(catan.id, 13)
        XCTAssertEqual(catan.yearPublished, 1995)
        XCTAssertEqual(catan.minPlayers, 3)
        XCTAssertEqual(catan.maxPlayers, 4)
        XCTAssertEqual(catan.playingMinutes, 120)
        XCTAssertEqual(catan.coverURL?.absoluteString, "https://cf.geekdo-images.com/catan.jpg", "protocol-relative URLs get https")
        XCTAssertEqual(catan.bggURL?.absoluteString, "https://boardgamegeek.com/boardgame/13")
        XCTAssertNil(results[1].playingMinutes, "a 0 playing time means unknown")

        let thing = try XCTUnwrap(ArtworkStubProtocol.requested.first { $0.path.hasSuffix("/thing") })
        XCTAssertTrue(thing.query?.contains("id=9999,13,27710") ?? false)
        XCTAssertTrue(thing.query?.contains("stats=1") ?? false)
    }

    func test_playerText() {
        XCTAssertEqual(BoardGameText.players(min: 2, max: 4), "2–4 players")
        XCTAssertEqual(BoardGameText.players(min: 1, max: 1), "1 player")
        XCTAssertEqual(BoardGameText.players(min: 2, max: nil), "2+ players")
        XCTAssertNil(BoardGameText.players(min: nil, max: nil))
        XCTAssertEqual(BoardGameText.secondary(year: 2017, minPlayers: 1, maxPlayers: 4), "2017 · 1–4 players")
    }

    @MainActor
    func test_boardGameRoundTripsThroughCSV() throws {
        let list = RankList(name: "Board games", category: .boardGames)
        var staged = StagedItem(name: "Wingspan", category: .boardGames)
        staged.boardGame = try XCTUnwrap(MockBoardGameSearchService.pool.first { $0.name == "Wingspan" })
        let item = RankItem(name: "Wingspan", bucket: .loved, score: 10)
        staged.apply(to: item)
        list.items = [item]

        let decoded = RankList(name: "Board games", category: .boardGames)
        try ListCSVCodec.decodeItems(into: decoded, from: ListCSVCodec.encodeItems(of: list))
        let round = try XCTUnwrap(decoded.items.first)
        round.list = decoded
        XCTAssertEqual(round.releaseYear, 2019)
        XCTAssertEqual(round.minPlayers, 1)
        XCTAssertEqual(round.maxPlayers, 5)
        XCTAssertEqual(round.playingMinutes, 70)
        XCTAssertEqual(round.primaryURL?.absoluteString, "https://boardgamegeek.com/boardgame/266192")
        XCTAssertEqual(RankingApplier.comparisonSecondaryText(for: round, in: decoded), "2019 · 1–5 players")
    }
}
