import UIKit
import XCTest
@testable import AnyRank

/// Place photos: referenced by place ID, resolved through
/// `PlacePhotos.loader`, and cached like any other artwork.
final class PlacePhotosTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        PlacePhotos.loader = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func test_photoReference_roundTripsThePlaceID() throws {
        let url = try XCTUnwrap(PlacePhotos.url(forPlaceID: "ChIJN1t_tDeuEmsRUsoyG83frY4").flatMap(URL.init(string:)))
        XCTAssertEqual(PlacePhotos.placeID(from: url), "ChIJN1t_tDeuEmsRUsoyG83frY4")
        XCTAssertNil(PlacePhotos.url(forPlaceID: nil))
        XCTAssertNil(PlacePhotos.placeID(from: URL(string: "https://example.com/x.jpg")!))
    }

    func test_photo_isLoadedOnce_thenServedFromDisk() async throws {
        let calls = Counter()
        PlacePhotos.loader = { _ in
            await calls.increment()
            return .image(Self.jpeg())
        }
        let url = URL(string: PlacePhotos.url(forPlaceID: "place-1")!)!

        guard case .image = await ArtworkCache(directory: directory).load(url) else { return XCTFail("expected a photo") }
        guard case .image = await ArtworkCache(directory: directory).load(url) else { return XCTFail("expected the disk copy") }
        let count = await calls.value
        XCTAssertEqual(count, 1)
    }

    func test_placeWithoutPhotos_isRemembered_failuresAreNot() async {
        let calls = Counter()
        PlacePhotos.loader = { id in
            await calls.increment()
            return id == "no-photos" ? .none : .failed
        }
        let none = URL(string: PlacePhotos.url(forPlaceID: "no-photos")!)!
        let flaky = URL(string: PlacePhotos.url(forPlaceID: "flaky")!)!

        let firstNone = await ArtworkCache(directory: directory).load(none)
        let secondNone = await ArtworkCache(directory: directory).load(none)
        XCTAssertEqual(firstNone, .missing)
        XCTAssertEqual(secondNone, .missing)
        let firstFlaky = await ArtworkCache(directory: directory).load(flaky)
        let secondFlaky = await ArtworkCache(directory: directory).load(flaky)
        XCTAssertEqual(firstFlaky, .failed)
        XCTAssertEqual(secondFlaky, .failed)
        let count = await calls.value
        XCTAssertEqual(count, 3, "the photo-less place is asked once, the failing one every time")
    }

    func test_withoutPlacesKey_showsPlaceholder_andTriesAgainLater() async {
        let url = URL(string: PlacePhotos.url(forPlaceID: "place-2")!)!
        let without = await ArtworkCache(directory: directory).load(url)
        XCTAssertEqual(without, .missing)

        PlacePhotos.loader = { _ in .image(Self.jpeg()) }
        guard case .image = await ArtworkCache(directory: directory).load(url) else {
            return XCTFail("a key added later should still produce the photo")
        }
    }

    @MainActor
    func test_placeLists_showPhotos_textCustomListsDoNot() {
        let item = RankItem(name: "Bestia", bucket: .loved)
        item.placeID = "abc"
        for list in [RankList(name: "R", category: .restaurants), RankList(name: "S", category: .stays),
                     RankList(name: "C", category: .custom, linksToMapsLocation: true)] {
            XCTAssertTrue(list.showsArtwork)
            XCTAssertEqual(RankingApplier.comparisonImageURLString(for: item, in: list), "places-photo://abc")
        }
        let textList = RankList(name: "Wines", category: .custom)
        XCTAssertFalse(textList.showsArtwork)
        XCTAssertNil(RankingApplier.comparisonImageURLString(for: item, in: textList))
    }

    private static func jpeg() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480), format: format).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        }
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
