import XCTest
@testable import AnyRank

/// Export → restore round trips for `ListArchive`, plus the `ZipWriter` it
/// packages with. Restoring reads through `ZipReader`, so these also check
/// that the two agree on the format.
final class ListArchiveTests: XCTestCase {

    func test_zipWriter_roundTripsThroughZipReader() throws {
        let entries = [
            ZipWriter.Entry(path: "folder/a.csv", data: Data("name,score\nBestia,9.5\n".utf8)),
            ZipWriter.Entry(path: "folder/ünïcode.json", data: Data("{}".utf8)),
            ZipWriter.Entry(path: "empty.txt", data: Data()),
        ]
        let archive = ZipWriter.archive(entries)

        XCTAssertTrue(ZipReader.isZip(archive))
        let read = try ZipReader.entries(in: archive)
        XCTAssertEqual(read.map(\.path), entries.map(\.path))
        XCTAssertEqual(read.map(\.data), entries.map(\.data))
    }

    func test_crc32_matchesKnownValue() {
        // The standard CRC-32 check value.
        XCTAssertEqual(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    @MainActor
    func test_export_thenRestore_preservesListsItemsAndComparisons() async throws {
        let restaurants = RankList(name: "Restaurants", category: .restaurants, rerankPromptThreshold: 7)
        let bestia = RankItem(name: "Bestia", bucket: .loved, score: 10)
        bestia.address = "2121 E 7th Pl"
        let republique = RankItem(name: "Republique", bucket: .loved, score: 8.5)
        restaurants.items = [bestia, republique]
        restaurants.comparisons = [ComparisonRecord(winnerItemID: bestia.id, loserItemID: republique.id, kind: .binarySearch)]

        let wines = RankList(name: "Wines", category: .custom, customFieldNames: ["Vintage", "Region"])
        let wine = RankItem(name: "Barolo", bucket: .liked, score: 7)
        wine.customFieldValues = ["Vintage": "2016", "Region": "Piedmont"]
        wines.items = [wine]

        let url = try await ListArchive.export([restaurants, wines])
        defer { try? FileManager.default.removeItem(at: url) }
        let restored = try await ListArchive.lists(fromArchive: Data(contentsOf: url))

        XCTAssertEqual(Set(restored.map(\.id)), [restaurants.id, wines.id])

        let r = try XCTUnwrap(restored.first { $0.id == restaurants.id })
        XCTAssertEqual(r.name, "Restaurants")
        XCTAssertEqual(r.category, .restaurants)
        XCTAssertEqual(r.rerankPromptThreshold, 7)
        XCTAssertEqual(r.items.map(\.id), [bestia.id, republique.id])
        XCTAssertEqual(r.items.map(\.score), [10, 8.5])
        XCTAssertEqual(r.items.first?.address, "2121 E 7th Pl")
        XCTAssertTrue(r.items.allSatisfy { $0.list === r })
        XCTAssertEqual(r.comparisons.map(\.winnerItemID), [bestia.id])

        let w = try XCTUnwrap(restored.first { $0.id == wines.id })
        XCTAssertEqual(w.customFieldNames, ["Vintage", "Region"])
        XCTAssertEqual(w.items.first?.customFieldValues, ["Vintage": "2016", "Region": "Piedmont"])
    }

    @MainActor
    func test_restore_toleratesFinderRecompression() async throws {
        let list = RankList(name: "Books", category: .books)
        list.items = [RankItem(name: "Beloved", bucket: .loved, score: 10)]
        let url = try await ListArchive.export([list])
        defer { try? FileManager.default.removeItem(at: url) }

        // Re-wrap the export's files the way Finder's "Compress" would:
        // a different folder name plus macOS metadata entries.
        let original = try ZipReader.entries(in: Data(contentsOf: url))
        var entries = original.map {
            ZipWriter.Entry(path: "Backup/" + ($0.path as NSString).lastPathComponent, data: $0.data)
        }
        entries.append(.init(path: "__MACOSX/Backup/._index.json", data: Data([0, 1, 2])))
        entries.append(.init(path: "Backup/.DS_Store", data: Data([0, 1, 2])))

        let restored = try await ListArchive.lists(fromArchive: ZipWriter.archive(entries))
        XCTAssertEqual(restored.map(\.id), [list.id])
        XCTAssertEqual(restored.first?.items.map(\.name), ["Beloved"])
    }

    @MainActor
    func test_restore_rejectsFilesThatAreNotExports() async {
        let notZip = Data("name\nBeloved\n".utf8)
        let otherZip = ZipWriter.archive([.init(path: "watched.csv", data: Data("Name,Year\n".utf8))])

        for data in [notZip, otherZip] {
            do {
                _ = try await ListArchive.lists(fromArchive: data)
                XCTFail("Expected notAnExport")
            } catch let error as ListArchive.ArchiveError {
                XCTAssertEqual(error, .notAnExport)
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
    }
}
