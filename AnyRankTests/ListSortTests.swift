import XCTest
@testable import AnyRank

/// The home screen's sort orders, and `lastUsedAt` surviving storage and
/// the Sheets index.
@MainActor
final class ListSortTests: XCTestCase {

    private func list(_ name: String, _ category: AnyRank.Category, usedHoursAgo: Double) -> RankList {
        RankList(
            name: name,
            category: category,
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: Date(timeIntervalSinceNow: -usedHoursAgo * 3600)
        )
    }

    private lazy var lists = [
        list("Restaurants — LA", .restaurants, usedHoursAgo: 30),
        list("wines", .custom, usedHoursAgo: 1),
        list("Books", .books, usedHoursAgo: 5),
        list("Albums", .albums, usedHoursAgo: 50),
        list("Anime", .anime, usedHoursAgo: 2),
        list("Bars", .bars, usedHoursAgo: 10),
    ]

    private func names(_ sections: [(category: AnyRank.Category?, lists: [RankList])]) -> [String] {
        sections.flatMap { $0.lists.map(\.name) }
    }

    func test_recent_isTheDefault_mostRecentFirst_flat() {
        let sections = ListSort().sections(lists)
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].category)
        XCTAssertEqual(names(sections), ["wines", "Anime", "Books", "Bars", "Restaurants — LA", "Albums"])
    }

    func test_recent_reversed_isLeastRecentFirst() {
        XCTAssertEqual(names(ListSort(order: .recent, reversed: true).sections(lists)),
                       ["Albums", "Restaurants — LA", "Bars", "Books", "Anime", "wines"])
    }

    func test_name_isAlphabetical_ignoringCase_andReversible() {
        XCTAssertEqual(names(ListSort(order: .name).sections(lists)),
                       ["Albums", "Anime", "Bars", "Books", "Restaurants — LA", "wines"])
        XCTAssertEqual(names(ListSort(order: .name, reversed: true).sections(lists)),
                       ["wines", "Restaurants — LA", "Books", "Bars", "Anime", "Albums"])
    }

    func test_type_groupsByCategoryAlphabetically_mostRecentWithinEach() {
        let extraBooks = list("Books — 2024", .books, usedHoursAgo: 3)
        let sections = ListSort(order: .type).sections(lists + [extraBooks])
        XCTAssertEqual(sections.map(\.category), [.albums, .anime, .bars, .books, .custom, .restaurants])
        XCTAssertEqual(sections[3].lists.map(\.name), ["Books — 2024", "Books"])

        let reversed = ListSort(order: .type, reversed: true).sections(lists + [extraBooks])
        XCTAssertEqual(reversed.map(\.category), [.restaurants, .custom, .books, .bars, .anime, .albums])
        XCTAssertEqual(reversed[2].lists.map(\.name), ["Books — 2024", "Books"], "direction flips the types, not the lists within one")
    }

    func test_touch_andMarkUsed_bumpLastUsed_butAddingDoesNot() {
        let repo = Repository(storage: MemoryListStorage())
        let old = Date(timeIntervalSince1970: 1_000)
        let list = RankList(name: "Wines", category: .custom, createdAt: old)
        repo.addList(list)
        XCTAssertEqual(list.lastUsedAt, old)

        repo.markUsed(list)
        XCTAssertGreaterThan(list.lastUsedAt, Date(timeIntervalSinceNow: -5))

        list.lastUsedAt = old
        repo.touch(list)
        XCTAssertGreaterThan(list.lastUsedAt, Date(timeIntervalSinceNow: -5))
    }

    func test_lastUsedAt_roundTripsThroughSheetsIndex() throws {
        let list = RankList(name: "Wines", category: .custom, createdAt: Date(timeIntervalSince1970: 1_000), lastUsedAt: Date(timeIntervalSince1970: 2_000))
        let entry = try XCTUnwrap(SheetsIndexCodec.decode(SheetsIndexCodec.encode(lists: [list])).first)
        XCTAssertEqual(entry.makeList().lastUsedAt.timeIntervalSince1970, 2_000, accuracy: 1)
    }

    func test_olderIndexWithoutLastUsed_fallsBackToCreatedAt() throws {
        let sheet = """
        id,name,category,created_at,custom_field_names,rerank_prompt_threshold,additions_since_last_rerank_prompt,links_to_maps_location
        \(UUID().uuidString),Wines,custom,1970-01-01T00:16:40Z,[],10,0,false
        """
        let fromSheet = try XCTUnwrap(SheetsIndexCodec.decode(sheet).first).makeList()
        XCTAssertEqual(fromSheet.lastUsedAt, fromSheet.createdAt)

        let json = #"[{"id":"\#(UUID().uuidString)","name":"Wines","category":"custom","createdAt":"1970-01-01T00:16:40Z","customFieldNames":[],"rerankPromptThreshold":10,"additionsSinceLastRerankPrompt":0}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fromDisk = try XCTUnwrap(decoder.decode([IndexEntry].self, from: Data(json.utf8)).first).makeList()
        XCTAssertEqual(fromDisk.lastUsedAt, fromDisk.createdAt)
    }
}
