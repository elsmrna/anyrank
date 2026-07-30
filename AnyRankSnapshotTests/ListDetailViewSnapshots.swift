import XCTest
import SwiftUI
import SnapshotTesting
@testable import AnyRank

final class ListDetailViewSnapshots: XCTestCase {

    @MainActor
    func test_fullList_allBuckets() {
        let repo = PreviewSupport.fullRestaurantsRepository()
        let list = repo.lists.first!
        let view = NavigationStack {
            ListDetailView(list: list)
        }
        .environment(repo)
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }

    @MainActor
    func test_singleItem_noScoresShown() {
        let repo = PreviewSupport.singleItemRepository()
        let list = repo.lists.first!
        let view = NavigationStack {
            ListDetailView(list: list)
        }
        .environment(repo)
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }

    @MainActor
    func test_emptyList() {
        let repo = PreviewSupport.emptyRepository()
        let list = RankList(name: "Restaurants", category: .restaurants)
        repo.addList(list)
        let view = NavigationStack {
            ListDetailView(list: list)
        }
        .environment(repo)
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }
}
