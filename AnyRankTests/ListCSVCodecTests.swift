import XCTest
@testable import AnyRank

/// Round-trip tests for `ListCSVCodec`. Encode a list to CSV, decode into
/// a fresh list, verify the contents survive. Also covers items with
/// metadata in every category-specific field set and custom-category lists
/// with user-defined columns.
final class ListCSVCodecTests: XCTestCase {

    @MainActor
    func test_restaurantsList_roundTrips() throws {
        let list = RankList(name: "Restaurants", category: .restaurants)
        let item = RankItem(name: "Bestia", bucket: .loved, score: 9.5)
        item.placeID = "ChIJabc"
        item.address = "2121 E 7th Pl"
        item.latitude = 34.03
        item.longitude = -118.23
        item.mapsURLString = "https://maps.google.com/?cid=123"
        item.notes = "great pasta"
        item.dateConsumed = Date(timeIntervalSince1970: 1_700_000_000)
        list.items = [item]
        item.list = list

        let csv = ListCSVCodec.encodeItems(of: list)

        let decoded = RankList(name: "Restaurants", category: .restaurants)
        try ListCSVCodec.decodeItems(into: decoded, from: csv)

        XCTAssertEqual(decoded.items.count, 1)
        let round = decoded.items[0]
        XCTAssertEqual(round.id, item.id)
        XCTAssertEqual(round.name, "Bestia")
        XCTAssertEqual(round.bucket, .loved)
        XCTAssertEqual(round.score, 9.5, accuracy: 0.001)
        XCTAssertEqual(round.placeID, "ChIJabc")
        XCTAssertEqual(round.address, "2121 E 7th Pl")
        XCTAssertEqual(round.latitude, 34.03)
        XCTAssertEqual(round.longitude, -118.23)
        XCTAssertEqual(round.mapsURLString, "https://maps.google.com/?cid=123")
        XCTAssertEqual(round.notes, "great pasta")
        XCTAssertEqual(round.dateConsumed?.timeIntervalSince1970 ?? .nan,
                       Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSince1970,
                       accuracy: 1.0)
    }

    @MainActor
    func test_moviesList_roundTrips() throws {
        let list = RankList(name: "Movies", category: .movies)
        let item = RankItem(name: "Inception", bucket: .loved, score: 9.8)
        item.tmdbID = 27205
        item.releaseYear = 2010
        item.imdbURLString = "https://www.imdb.com/title/tt1375666/"
        list.items = [item]
        item.list = list

        let csv = ListCSVCodec.encodeItems(of: list)
        let decoded = RankList(name: "Movies", category: .movies)
        try ListCSVCodec.decodeItems(into: decoded, from: csv)

        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items[0].tmdbID, 27205)
        XCTAssertEqual(decoded.items[0].releaseYear, 2010)
        XCTAssertEqual(decoded.items[0].imdbURLString, "https://www.imdb.com/title/tt1375666/")
    }

    @MainActor
    func test_booksList_roundTrips() throws {
        let list = RankList(name: "Books", category: .books)
        let item = RankItem(name: "The Great Gatsby", bucket: .loved, score: 9.2)
        item.author = "F. Scott Fitzgerald"
        item.releaseYear = 1925
        item.isbn = "9780743273565"
        item.storyGraphURLString = "https://app.thestorygraph.com/books/the-great-gatsby"
        list.items = [item]
        item.list = list

        let csv = ListCSVCodec.encodeItems(of: list)
        let decoded = RankList(name: "Books", category: .books)
        try ListCSVCodec.decodeItems(into: decoded, from: csv)

        XCTAssertEqual(decoded.items.count, 1)
        let round = decoded.items[0]
        XCTAssertEqual(round.name, "The Great Gatsby")
        XCTAssertEqual(round.author, "F. Scott Fitzgerald")
        XCTAssertEqual(round.releaseYear, 1925)
        XCTAssertEqual(round.isbn, "9780743273565")
        XCTAssertEqual(round.storyGraphURLString, "https://app.thestorygraph.com/books/the-great-gatsby")
    }

    @MainActor
    func test_customList_withFields_roundTrips() throws {
        let list = RankList(
            name: "Wines",
            category: .custom,
            customFieldNames: ["Region", "Vintage", "Grape"]
        )
        let item = RankItem(name: "A1", bucket: .liked, score: 7.2)
        item.customLinkString = "https://example.com/wine"
        item.customFieldValues = [
            "Region": "Burgundy",
            "Vintage": "2018",
            "Grape": "Pinot Noir"
        ]
        list.items = [item]
        item.list = list

        let csv = ListCSVCodec.encodeItems(of: list)
        let decoded = RankList(
            name: "Wines",
            category: .custom,
            customFieldNames: ["Region", "Vintage", "Grape"]
        )
        try ListCSVCodec.decodeItems(into: decoded, from: csv)

        XCTAssertEqual(decoded.items.count, 1)
        let round = decoded.items[0]
        XCTAssertEqual(round.customLinkString, "https://example.com/wine")
        XCTAssertEqual(round.customFieldValues["Region"], "Burgundy")
        XCTAssertEqual(round.customFieldValues["Vintage"], "2018")
        XCTAssertEqual(round.customFieldValues["Grape"], "Pinot Noir")
    }

    @MainActor
    func test_comparisons_roundTrip() throws {
        let list = RankList(name: "Restaurants", category: .restaurants)
        let winnerID = UUID()
        let loserID = UUID()
        let record = ComparisonRecord(
            winnerItemID: winnerID,
            loserItemID: loserID,
            kind: .binarySearch
        )
        list.comparisons = [record]

        let csv = ListCSVCodec.encodeComparisons(of: list)

        let decoded = RankList(name: "Restaurants", category: .restaurants)
        try ListCSVCodec.decodeComparisons(into: decoded, from: csv)

        XCTAssertEqual(decoded.comparisons.count, 1)
        XCTAssertEqual(decoded.comparisons[0].winnerItemID, winnerID)
        XCTAssertEqual(decoded.comparisons[0].loserItemID, loserID)
        XCTAssertEqual(decoded.comparisons[0].kind, .binarySearch)
    }

    @MainActor
    func test_nameWithCommaAndQuote_survivesRoundTrip() throws {
        // Items with messy names should survive — a Place named
        // "Joe's "House", LLC" shouldn't break the CSV parser.
        let list = RankList(name: "Restaurants", category: .restaurants)
        let item = RankItem(name: "Joe's \"House\", LLC", bucket: .fine, score: 4.5)
        list.items = [item]
        item.list = list

        let csv = ListCSVCodec.encodeItems(of: list)
        let decoded = RankList(name: "Restaurants", category: .restaurants)
        try ListCSVCodec.decodeItems(into: decoded, from: csv)

        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items[0].name, "Joe's \"House\", LLC")
    }

    @MainActor
    func test_emptyList_encodesHeaderOnly() throws {
        let list = RankList(name: "Empty", category: .restaurants)
        let csv = ListCSVCodec.encodeItems(of: list)

        let rows = try CSV.decode(csv)
        XCTAssertEqual(rows.count, 1) // Just the header.
        XCTAssertEqual(rows[0], ListCSVCodec.columnHeaders(for: list))
    }
}
