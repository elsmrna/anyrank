import XCTest
@testable import AnyRank

/// Tests for `SheetsIndexCodec` — the encoder for the `_index` tab that
/// carries list-level metadata to the synced spreadsheet. Round-trip
/// coverage is the main goal because the index tab is the only place the
/// remote knows what category a list is.
final class SheetsIndexCodecTests: XCTestCase {

    @MainActor
    func test_emptyLists_encodesHeaderOnly() throws {
        let csv = SheetsIndexCodec.encode(lists: [])
        let rows = try CSV.decode(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0], SheetsIndexCodec.columnHeaders)
    }

    @MainActor
    func test_singleList_roundTrips() throws {
        let list = RankList(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Restaurants — NYC",
            category: .restaurants,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            customFieldNames: [],
            rerankPromptThreshold: 8
        )
        let csv = SheetsIndexCodec.encode(lists: [list])
        let entries = try SheetsIndexCodec.decode(csv)

        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.id, list.id)
        XCTAssertEqual(entry.name, "Restaurants — NYC")
        XCTAssertEqual(entry.category, "restaurants")
        XCTAssertEqual(entry.rerankPromptThreshold, 8)
    }

    @MainActor
    func test_customFieldNames_withCommasAndQuotes_survive() throws {
        // The whole reason we JSON-encode custom field names: they can
        // contain characters that would otherwise break the CSV.
        let nasty = ["Region, French", "Year \"vintage\"", "Plain"]
        let list = RankList(
            name: "Wines",
            category: .custom,
            customFieldNames: nasty
        )
        let csv = SheetsIndexCodec.encode(lists: [list])
        let entries = try SheetsIndexCodec.decode(csv)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].customFieldNames, nasty)
    }

    @MainActor
    func test_multipleLists_orderedByCreatedAt() throws {
        let oldest = RankList(
            name: "Oldest",
            category: .restaurants,
            createdAt: Date(timeIntervalSince1970: 1_000_000_000)
        )
        let middle = RankList(
            name: "Middle",
            category: .movies,
            createdAt: Date(timeIntervalSince1970: 1_500_000_000)
        )
        let newest = RankList(
            name: "Newest",
            category: .bars,
            createdAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        // Pass in arbitrary order; the encoder sorts ascending.
        let csv = SheetsIndexCodec.encode(lists: [newest, oldest, middle])
        let entries = try SheetsIndexCodec.decode(csv)

        XCTAssertEqual(entries.map(\.name), ["Oldest", "Middle", "Newest"])
    }

    @MainActor
    func test_linksToMapsLocation_roundTrips_both_values() throws {
        let mapsList = RankList(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Weekend Spots",
            category: .custom,
            customFieldNames: ["Vibe"],
            linksToMapsLocation: true
        )
        let plainList = RankList(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "Reading Notes",
            category: .custom,
            customFieldNames: [],
            linksToMapsLocation: false
        )

        let csv = SheetsIndexCodec.encode(lists: [mapsList, plainList])
        let entries = try SheetsIndexCodec.decode(csv).sorted { $0.name < $1.name }

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "Reading Notes")
        XCTAssertEqual(entries[0].linksToMapsLocation, false)
        XCTAssertEqual(entries[1].name, "Weekend Spots")
        XCTAssertEqual(entries[1].linksToMapsLocation, true)
    }

    @MainActor
    func test_legacySheet_without_linksColumn_decodes_as_false() throws {
        // Older sheets — written before the column existed — only have
        // seven columns. The decoder should treat the missing column as
        // false rather than rejecting the row.
        let legacyHeader = "id,name,category,created_at,custom_field_names,rerank_prompt_threshold,additions_since_last_rerank_prompt"
        let uuid = "55555555-5555-5555-5555-555555555555"
        let row = "\(uuid),Legacy List,restaurants,2023-01-01T00:00:00Z,,10,0"
        let csv = "\(legacyHeader)\n\(row)\n"

        let entries = try SheetsIndexCodec.decode(csv)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].linksToMapsLocation, false)
    }

    func test_malformedRow_isSkipped_notFatal() throws {
        // Manually craft a CSV with one good row and one bad (missing id).
        let header = SheetsIndexCodec.columnHeaders.joined(separator: ",")
        let validUUID = "22222222-2222-2222-2222-222222222222"
        let good = "\(validUUID),GoodList,restaurants,2023-01-01T00:00:00Z,,10,0"
        let bad = ",MissingID,restaurants,2023-01-01T00:00:00Z,,10,0"
        let csv = "\(header)\n\(good)\n\(bad)\n"

        let entries = try SheetsIndexCodec.decode(csv)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "GoodList")
    }
}
