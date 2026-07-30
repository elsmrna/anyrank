import XCTest
import SwiftUI
import SnapshotTesting
@testable import AnyRank

final class ComparisonScreenSnapshots: XCTestCase {

    @MainActor
    func test_binarySearchComparison() {
        let snapshot = RankingSession.ListSnapshot(bucketContents: [
            .loved: [
                .init(id: UUID(), name: "Bestia"),
                .init(id: UUID(), name: "Republique"),
                .init(id: UUID(), name: "Kismet")
            ]
        ])
        let session = RankingSession(snapshot: snapshot, newItemID: UUID())
        session.selectBucket(.loved)
        let view = ComparisonScreen(
            newItemName: "Sushi Note",
            session: session,
            onAnswer: { _ in }
        )
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }

    @MainActor
    func test_bucketPicker() {
        let view = BucketPickerScreen(itemName: "Sushi Note", onPick: { _ in })
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }

    @MainActor
    func test_resultScreen_withScore() {
        let view = AddItemResultScreen(
            stagedName: "Sushi Note",
            placement: .init(bucket: .loved, rankInBucket: 1, comparisons: [
                .init(winnerItemID: UUID(), loserItemID: UUID(), kind: .binarySearch),
                .init(winnerItemID: UUID(), loserItemID: UUID(), kind: .binarySearch)
            ]),
            onDone: {}
        )
        let host = UIHostingController(rootView: view)
        assertSnapshot(
            of: host,
            as: .image(on: SnapshotConfig.device, precision: SnapshotConfig.precision)
        )
    }
}
