import XCTest
@testable import AnyRank

final class FileImporterTests: XCTestCase {

    func test_letterboxdDiary_collapsesRewatchesAndSuggestsBuckets() throws {
        let csv = """
        Date,Name,Year,Letterboxd URI,Rating,Rewatch,Tags,Watched Date
        2024-01-02,Past Lives,2023,https://boxd.it/aaa,4.5,,,2024-01-01
        2024-02-02,Dune,2021,https://boxd.it/bbb,3,,,2024-02-01
        2024-03-02,Past Lives,2023,https://boxd.it/aaa,5,Yes,,2024-03-01
        2024-04-02,Cats,2019,https://boxd.it/ccc,1,,,2024-04-01
        """
        let candidates = try FileImporters.letterboxd(csv)
        XCTAssertEqual(candidates.map(\.item.name), ["Past Lives", "Dune", "Cats"])
        let pastLives = candidates[0].item
        XCTAssertEqual(pastLives.suggestedBucket, .loved)
        XCTAssertEqual(pastLives.sourceNote, "Rated ★★★★★ on Letterboxd")
        XCTAssertEqual(pastLives.fallbackYear, 2023)
        XCTAssertEqual(pastLives.sourceURL?.absoluteString, "https://boxd.it/aaa")
        XCTAssertEqual(candidates[1].item.suggestedBucket, .fine)
        XCTAssertEqual(candidates[2].item.suggestedBucket, .didntLike)
    }

    func test_letterboxd_rejectsOtherFiles() {
        XCTAssertThrowsError(try FileImporters.letterboxd("Title,Author\nA,B\n"))
    }

    func test_goodreads_importsReadShelfOnly_andCleansISBN() throws {
        let csv = #"""
        Book Id,Title,Author,ISBN,ISBN13,My Rating,Year Published,Original Publication Year,Date Read,Exclusive Shelf,My Review
        1,Beloved,Toni Morrison,"=""1400033411""","=""9781400033416""",5,2004,1987,2023/05/01,read,Haunting.
        2,Dune,Frank Herbert,"=""""","=""""",0,1990,1965,,to-read,
        3,Pachinko,Min Jin Lee,,,4,2017,2017,,read,
        """#
        let candidates = try FileImporters.goodreads(csv)
        XCTAssertEqual(candidates.map(\.item.name), ["Beloved", "Pachinko"])
        let beloved = candidates[0].item
        XCTAssertEqual(beloved.book?.isbn, "9781400033416")
        XCTAssertEqual(beloved.book?.publicationYear, 1987)
        XCTAssertEqual(beloved.suggestedBucket, .loved)
        XCTAssertEqual(beloved.notes, "Haunting.")
        XCTAssertNotNil(beloved.dateConsumed)
        XCTAssertEqual(beloved.sourceURL?.absoluteString, "https://www.goodreads.com/book/show/1")
        XCTAssertEqual(candidates[1].item.suggestedBucket, .liked)
    }

    func test_storyGraph_quarterStarsRoundToNearestBucket() throws {
        let csv = """
        Title,Authors,ISBN/UID,Read Status,Star Rating,Last Date Read
        Piranesi,Susanna Clarke,9781635575637,read,4.25,2022/01/01
        Circe,Madeline Miller,,to-read,,
        """
        let candidates = try FileImporters.storyGraph(csv)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].item.suggestedBucket, .liked)
        XCTAssertEqual(candidates[0].item.book?.author, "Susanna Clarke")
    }

    func test_pastedList_stripsMarkersAndBlanks() {
        let text = "1. Spirited Away\n\n- Perfect Blue\n• Your Name\n  Akira  \n2) Paprika"
        let names = FileImporters.pastedList(text, category: .anime).map(\.item.name)
        XCTAssertEqual(names, ["Spirited Away", "Perfect Blue", "Your Name", "Akira", "Paprika"])
    }

    func test_crlfExportsParse() throws {
        let csv = "Name,Year,Letterboxd URI,Rating\r\nHer,2013,https://boxd.it/h,4\r\n"
        XCTAssertEqual(try FileImporters.letterboxd(csv).map(\.item.name), ["Her"])
    }
}

final class ImportMatcherTests: XCTestCase {

    func test_normalize() {
        XCTAssertEqual(ImportMatcher.normalize("The Witcher® 3: Wild Hunt"), "witcher 3 wild hunt")
        XCTAssertEqual(ImportMatcher.normalize("ELDEN RING"), "elden ring")
        XCTAssertEqual(ImportMatcher.normalize("Amélie"), "amelie")
        XCTAssertEqual(ImportMatcher.normalize("Death & Co"), "death and co")
        XCTAssertEqual(ImportMatcher.normalize("The The"), "the")
    }

    private func movie(_ name: String, year: Int?) -> StagedItem {
        var item = StagedItem(name: name, category: .movies)
        item.fallbackYear = year
        return item
    }

    @MainActor
    func test_plan_skipsItemsAlreadyInList_respectingYears() {
        let list = RankList(name: "Films", category: .movies)
        let existing = RankItem(name: "Dune", bucket: .liked)
        existing.releaseYear = 2021
        existing.list = list
        list.items.append(existing)

        let plan = ImportMatcher.plan(
            candidates: [
                ImportCandidate(item: movie("Dune", year: 2021)),
                ImportCandidate(item: movie("Dune", year: 1984)),
                ImportCandidate(item: movie("Her", year: 2013)),
                ImportCandidate(item: movie("her", year: 2013)),
            ],
            target: list,
            alreadyQueued: [],
            skipNeverEngaged: true
        )
        XCTAssertEqual(plan.toRank.map(\.fallbackYear), [1984, 2013])
        XCTAssertEqual(plan.alreadyInList, 1)
        XCTAssertEqual(plan.repeatedInSource, 1)
    }

    @MainActor
    func test_plan_neverEngagedToggle() {
        let games = SteamImport.candidates(from: [
            SteamOwnedGame(appID: 1, name: "Played", minutesPlayed: 90, lastPlayed: nil),
            SteamOwnedGame(appID: 2, name: "Backlog", minutesPlayed: 0, lastPlayed: nil),
        ])
        let skipping = ImportMatcher.plan(candidates: games, target: nil, alreadyQueued: [], skipNeverEngaged: true)
        XCTAssertEqual(skipping.toRank.map(\.name), ["Played"])
        XCTAssertEqual(skipping.skippedNeverEngaged, 1)
        let keeping = ImportMatcher.plan(candidates: games, target: nil, alreadyQueued: [], skipNeverEngaged: false)
        XCTAssertEqual(keeping.toRank.count, 2)
    }

    @MainActor
    func test_sourceURLMatchesDespiteRename() {
        let list = RankList(name: "Games", category: .games)
        let existing = RankItem(name: "My favorite game", bucket: .loved)
        existing.sourceURLString = SteamImport.storeURL(appID: 42)?.absoluteString
        existing.list = list
        list.items.append(existing)
        let candidate = SteamImport.candidates(from: [
            SteamOwnedGame(appID: 42, name: "Something Else", minutesPlayed: 10, lastPlayed: nil)
        ])[0].item
        XCTAssertTrue(ImportMatcher.list(list, contains: candidate))
    }

    func test_placesWithSameNameDifferentAddressAreDistinct() {
        func place(_ id: String, _ address: String) -> StagedItem {
            var item = StagedItem(name: "Starbucks", category: .restaurants)
            item.place = PlaceSearchResult(id: id, name: "Starbucks", address: address, latitude: 0, longitude: 0, mapsURL: URL(string: "https://maps.google.com")!)
            return item
        }
        let kept = ImportMatcher.removingMatches([place("b", "2 Oak St")], against: [place("a", "1 Main St")])
        XCTAssertEqual(kept.count, 1)
    }
}

final class SteamImportTests: XCTestCase {

    func test_parseProfile() {
        XCTAssertEqual(SteamImport.parseProfile("https://steamcommunity.com/id/gaben/"), .vanity("gaben"))
        XCTAssertEqual(SteamImport.parseProfile("https://steamcommunity.com/profiles/76561197960287930"), .steamID("76561197960287930"))
        XCTAssertEqual(SteamImport.parseProfile("76561197960287930"), .steamID("76561197960287930"))
        XCTAssertEqual(SteamImport.parseProfile("gaben"), .vanity("gaben"))
        XCTAssertNil(SteamImport.parseProfile("   "))
    }

    func test_candidatesOrderedByPlaytime() {
        let candidates = SteamImport.candidates(from: [
            SteamOwnedGame(appID: 1, name: "B", minutesPlayed: 10, lastPlayed: nil),
            SteamOwnedGame(appID: 2, name: "A", minutesPlayed: 500, lastPlayed: nil),
            SteamOwnedGame(appID: 3, name: "C", minutesPlayed: 10, lastPlayed: nil),
        ])
        XCTAssertEqual(candidates.map(\.item.name), ["A", "B", "C"])
        XCTAssertEqual(candidates[0].item.sourceNote, "8.3 hours played")
        XCTAssertEqual(candidates[0].item.artworkURLString, SteamImport.coverURL(appID: 2)?.absoluteString)
    }
}

final class ImportStoreTests: XCTestCase {

    private func items(_ names: [String]) -> [StagedItem] {
        names.map { StagedItem(name: $0, category: .custom) }
    }

    func test_queueLifecycle() {
        let store = ImportStore()
        let listID = UUID()
        let queued = items(["A", "B", "C"])
        store.enqueue(queued, into: listID, from: .pastedList)

        store.deferItem(queued[0].id, in: listID)
        XCTAssertEqual(store.session(for: listID)?.pending.map(\.name), ["B", "C", "A"])

        store.markRanked(queued[1].id, in: listID)
        store.remove(queued[2].id, from: listID)
        let session = store.session(for: listID)
        XCTAssertEqual(session?.rankedCount, 1)
        XCTAssertEqual(session?.removedCount, 1)
        XCTAssertEqual(session?.total, 3)

        store.markRanked(queued[0].id, in: listID)
        XCTAssertNil(store.session(for: listID), "an emptied queue completes the import")
    }

    func test_enqueueMergesWithoutDuplicates() {
        let store = ImportStore()
        let listID = UUID()
        store.enqueue(items(["A", "B"]), into: listID, from: .pastedList)
        store.enqueue(items(["b", "C"]), into: listID, from: .pastedList)
        XCTAssertEqual(store.session(for: listID)?.pending.map(\.name), ["A", "B", "C"])
    }

    func test_abandon() {
        let store = ImportStore()
        let listID = UUID()
        store.enqueue(items(["A"]), into: listID, from: .pastedList)
        store.abandon(listID)
        XCTAssertNil(store.session(for: listID))
    }

    func test_persistsAcrossLaunches() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("imports.json")
        let listID = UUID()
        var item = StagedItem(name: "Hades", category: .games)
        item.suggestedBucket = .loved
        item.sourceNote = "67 hours played"

        let first = ImportStore(fileURL: url)
        first.enqueue([item], into: listID, from: .steam)
        first.waitForPendingWrites()

        let second = ImportStore(fileURL: url)
        let session = try XCTUnwrap(second.session(for: listID))
        XCTAssertEqual(session.source, .steam)
        XCTAssertEqual(session.pending, [item])
    }
}
