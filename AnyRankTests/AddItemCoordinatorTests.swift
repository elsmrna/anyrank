import XCTest
@testable import AnyRank

/// The add/re-rank sheets drive a `NavigationStack` from the coordinator's
/// `path`. These tests pin down that mapping, and that shrinking the path
/// (back button / edge swipe) steps the state machine back to match.
@MainActor
final class AddItemCoordinatorTests: XCTestCase {

    private func makeList(lovedCount: Int) -> RankList {
        let list = RankList(name: "Test", category: .restaurants)
        for i in 0..<lovedCount {
            let item = RankItem(name: "Item \(i)", bucket: .loved, score: 10 - Double(i))
            item.list = list
            list.items.append(item)
        }
        return list
    }

    func test_addFlow_pathFollowsPhases() {
        let coordinator = AddItemCoordinator(list: makeList(lovedCount: 3))
        XCTAssertEqual(coordinator.path, [])

        coordinator.itemIdentified(StagedItem(name: "New", category: .restaurants))
        XCTAssertEqual(coordinator.path, [.bucketPick])

        coordinator.bucketPicked(.loved)
        XCTAssertEqual(coordinator.path, [.bucketPick, .comparing])
        XCTAssertNotNil(coordinator.session)
    }

    func test_addFlow_poppingPathStepsBack() {
        let coordinator = AddItemCoordinator(list: makeList(lovedCount: 3))
        coordinator.itemIdentified(StagedItem(name: "New", category: .restaurants))
        coordinator.bucketPicked(.loved)

        coordinator.path = [.bucketPick]
        guard case .bucketPick = coordinator.phase else { return XCTFail("expected bucketPick") }
        // Staged item survives so the popped screen keeps rendering.
        XCTAssertEqual(coordinator.staged?.name, "New")

        coordinator.path = []
        guard case .identifying = coordinator.phase else { return XCTFail("expected identifying") }
    }

    func test_addFlow_poppingToRootFromComparisonStepsBackTwice() {
        let coordinator = AddItemCoordinator(list: makeList(lovedCount: 3))
        coordinator.itemIdentified(StagedItem(name: "New", category: .restaurants))
        coordinator.bucketPicked(.loved)

        coordinator.path = []
        guard case .identifying = coordinator.phase else { return XCTFail("expected identifying") }
    }

    func test_emptyBucket_finishesWithoutComparisonStep() {
        let coordinator = AddItemCoordinator(list: makeList(lovedCount: 0))
        coordinator.itemIdentified(StagedItem(name: "New", category: .restaurants))
        coordinator.bucketPicked(.fine)

        XCTAssertTrue(coordinator.isFinished)
        XCTAssertEqual(coordinator.path, [.bucketPick])
    }

    func test_rerank_rootIsBucketPicker() {
        let list = makeList(lovedCount: 4)
        let item = list.items[0]
        let coordinator = AddItemCoordinator(rerank: item, in: list)

        XCTAssertEqual(coordinator.path, [])
        XCTAssertFalse(coordinator.canGoBack)
        XCTAssertFalse(coordinator.back())

        coordinator.bucketPicked(.loved)
        XCTAssertEqual(coordinator.path, [.comparing])

        coordinator.path = []
        guard case .bucketPick(let staged) = coordinator.phase else { return XCTFail("expected bucketPick") }
        XCTAssertEqual(staged.id, item.id)
    }

    func test_rerank_excludesItemFromComparisons() {
        let list = makeList(lovedCount: 2)
        let item = list.items[0]
        let coordinator = AddItemCoordinator(rerank: item, in: list)
        coordinator.bucketPicked(.loved)

        guard case .askingComparison(let against, _) = coordinator.session?.state else {
            return XCTFail("expected a comparison")
        }
        XCTAssertNotEqual(against.id, item.id)
    }
}
