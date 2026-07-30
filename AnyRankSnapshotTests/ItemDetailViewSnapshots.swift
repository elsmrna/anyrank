import XCTest
import SwiftUI
import SnapshotTesting
@testable import AnyRank

final class ItemDetailViewSnapshots: XCTestCase {

    @MainActor
    func test_lovedItem_withScore() {
        let repo = PreviewSupport.fullRestaurantsRepository()
        let list = repo.lists.first!
        let item = list.itemsSortedByScore().first!
        let view = NavigationStack {
            ItemDetailView(item: item, list: list)
        }
        .environment(repo)
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }

    @MainActor
    func test_singleBucketItem_noScoreYet() {
        let repo = PreviewSupport.singleItemRepository()
        let list = repo.lists.first!
        let item = list.items.first!
        let view = NavigationStack {
            ItemDetailView(item: item, list: list)
        }
        .environment(repo)
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }
}
