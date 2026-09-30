import XCTest
@testable import AnyRank

/// Tests for the ranking state machine. Each test drives a fresh session
/// through a sequence of bucket pick + comparison answers, then asserts the
/// final placement (bucket and rank within bucket) and the comparison log.
///
/// All randomness is injected via `randomSource` so tests are deterministic.
final class RankingSessionTests: XCTestCase {

    // MARK: Helpers

    private func makeRefs(_ names: [String]) -> [RankingSession.ItemRef] {
        names.map { RankingSession.ItemRef(id: UUID(), name: $0) }
    }

    private func snapshot(_ pairs: [(Bucket, [RankingSession.ItemRef])]) -> RankingSession.ListSnapshot {
        var dict: [Bucket: [RankingSession.ItemRef]] = [:]
        for (bucket, refs) in pairs {
            dict[bucket] = refs
        }
        return .init(bucketContents: dict)
    }

    @MainActor
    private func assertFinished(
        _ session: RankingSession,
        bucket: Bucket,
        rank: Int,
        comparisonCount: Int? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard case .finished(let placement) = session.state else {
            XCTFail("Expected finished, got \(session.state)", file: file, line: line)
            return
        }
        XCTAssertEqual(placement.bucket, bucket, file: file, line: line)
        XCTAssertEqual(placement.rankInBucket, rank, file: file, line: line)
        if let comparisonCount {
            XCTAssertEqual(placement.comparisons.count, comparisonCount, file: file, line: line)
        }
    }

    // MARK: Empty list

    @MainActor
    func test_emptyList_emptyBucket_finishesImmediately() {
        let newID = UUID()
        let session = RankingSession(snapshot: .empty, newItemID: newID)
        session.selectBucket(.liked)

        assertFinished(session, bucket: .liked, rank: 0, comparisonCount: 0)
    }

    @MainActor
    func test_pickedBucketEmpty_otherBucketHasItems_runsBoundaryCheck() {
        // Picked Liked (empty), Loved has 2 items above. Boundary check upward
        // should fire because position 0 is at the top of an empty bucket.
        let lovedItems = makeRefs(["A", "B"])
        let snap = snapshot([(.loved, lovedItems)])
        let newID = UUID()
        let session = RankingSession(snapshot: snap, newItemID: newID)
        session.selectBucket(.liked)

        guard case .askingComparison(let against, let kind) = session.state else {
            return XCTFail("Expected boundary-check comparison, got \(session.state)")
        }
        XCTAssertEqual(kind, .boundaryCheck)
        // Should compare against the bottom of the Loved bucket — which is "B" (loved is sorted desc).
        XCTAssertEqual(against.name, "B")

        // If the new item loses, it stays in Liked at position 0.
        session.answerComparison(winner: against.id)
        assertFinished(session, bucket: .liked, rank: 0, comparisonCount: 1)
    }

    @MainActor
    func test_pickedBucketEmpty_promoteOnBoundary() {
        let lovedItems = makeRefs(["A", "B"])
        let snap = snapshot([(.loved, lovedItems)])
        let newID = UUID()
        let session = RankingSession(snapshot: snap, newItemID: newID)
        session.selectBucket(.liked)

        // Boundary comparison fires; new item wins → promoted into Loved at the bottom.
        session.answerComparison(winner: newID)
        assertFinished(session, bucket: .loved, rank: 2, comparisonCount: 1)
    }

    // MARK: Single-item bucket

    @MainActor
    func test_singleItemBucket_newWins_placedAtTop() {
        let lovedItems = makeRefs(["Existing"])
        let snap = snapshot([(.loved, lovedItems)])
        let newID = UUID()
        let session = RankingSession(snapshot: snap, newItemID: newID)
        session.selectBucket(.loved)

        // One binary-search comparison against the only item.
        guard case .askingComparison(let against, .binarySearch) = session.state else {
            return XCTFail("Expected binary-search comparison")
        }
        XCTAssertEqual(against.name, "Existing")

        session.answerComparison(winner: newID)
        // No bucket above Loved, so no boundary check. Placed at top.
        assertFinished(session, bucket: .loved, rank: 0, comparisonCount: 1)
    }

    @MainActor
    func test_singleItemBucket_newLoses_placedAtBottom_thenBoundaryDownward() {
        let lovedItems = makeRefs(["Existing"])
        // Liked has items so a downward boundary check from Loved bottom should fire.
        let likedItems = makeRefs(["L1"])
        let snap = snapshot([(.loved, lovedItems), (.liked, likedItems)])
        let newID = UUID()
        let session = RankingSession(snapshot: snap, newItemID: newID)
        session.selectBucket(.loved)

        // Lose to Existing → position 1 (bottom). Then boundary downward fires.
        guard case .askingComparison(let against, _) = session.state else {
            return XCTFail()
        }
        session.answerComparison(winner: against.id)

        // Now expect a boundary-check comparison with the top of Liked.
        guard case .askingComparison(let boundaryOpponent, .boundaryCheck) = session.state else {
            return XCTFail("Expected boundary-check, got \(session.state)")
        }
        XCTAssertEqual(boundaryOpponent.name, "L1")
        // If new wins, stays in Loved at position 1.
        session.answerComparison(winner: newID)
        assertFinished(session, bucket: .loved, rank: 1, comparisonCount: 2)
    }

    @MainActor
    func test_singleItemBucket_newLoses_demotedOnBoundary() {
        let lovedItems = makeRefs(["Existing"])
        let likedItems = makeRefs(["L1"])
        let snap = snapshot([(.loved, lovedItems), (.liked, likedItems)])
        let newID = UUID()
        let session = RankingSession(snapshot: snap, newItemID: newID)
        session.selectBucket(.loved)

        guard case .askingComparison(let against, _) = session.state else { return XCTFail() }
        session.answerComparison(winner: against.id)
        // Lose the boundary check → demoted to Liked at the top.
        guard case .askingComparison(let boundaryOpponent, .boundaryCheck) = session.state else {
            return XCTFail()
        }
        session.answerComparison(winner: boundaryOpponent.id)
        assertFinished(session, bucket: .liked, rank: 0, comparisonCount: 2)
    }

    // MARK: Multi-item bucket — exact binary search

    @MainActor
    func test_threeItemBucket_landsInMiddle() {
        // Loved has [A, B, C] sorted desc. New item should land at position 1.
        // First comparison: vs items[1] (B). Say new beats B → hi=1, lo=0.
        // Second comparison: vs items[0] (A). Say A beats new → lo=1, hi=1. Done.
        // Position = 1.
        let lovedItems = makeRefs(["A", "B", "C"])
        let snap = snapshot([(.loved, lovedItems)])
        let newID = UUID()
        let session = RankingSession(snapshot: snap, newItemID: newID)
        session.selectBucket(.loved)

        guard case .askingComparison(let opp1, _) = session.state else { return XCTFail() }
        XCTAssertEqual(opp1.name, "B")
        session.answerComparison(winner: newID)

        guard case .askingComparison(let opp2, _) = session.state else { return XCTFail() }
        XCTAssertEqual(opp2.name, "A")
        session.answerComparison(winner: opp2.id)

        assertFinished(session, bucket: .loved, rank: 1, comparisonCount: 2)
    }

    @MainActor
    func test_fourItemBucket_landsAtBottom_noBoundaryCheckIfNoLowerBucket() {
        // didntLike is the lowest bucket. No bucketBelow.
        let items = makeRefs(["A", "B", "C", "D"])
        let snap = snapshot([(.didntLike, items)])
        let newID = UUID()
        let session = RankingSession(snapshot: snap, newItemID: newID)
        session.selectBucket(.didntLike)

        // Drive the search such that the new item loses every comparison
        // → hi stays 4, lo advances. After all comparisons lose to mid
        // items, lo eventually equals hi == 4 (insertion at bottom).
        // First mid: 2 (C). Lose. lo=3.
        // Second mid: 3 (D). Lose. lo=4 == hi. Done.
        guard case .askingComparison(let o1, _) = session.state else { return XCTFail() }
        XCTAssertEqual(o1.name, "C")
        session.answerComparison(winner: o1.id)

        guard case .askingComparison(let o2, _) = session.state else { return XCTFail() }
        XCTAssertEqual(o2.name, "D")
        session.answerComparison(winner: o2.id)

        assertFinished(session, bucket: .didntLike, rank: 4, comparisonCount: 2)
    }

    // MARK: Comparison cap + tie-break

    /// 100-item Fine bucket with the cap at 5, so bisection can't converge.
    /// New wins every bisection round: hi shrinks 100 → 50 → 25 → 12 → 6 → 3,
    /// leaving the unresolved range [0, 3). With randomSource() = 0.5 the
    /// tie-break index is 0 + Int(0.5 * 3) = 1.
    @MainActor
    private func sessionAtTieBreak() -> (RankingSession, UUID) {
        var refs: [RankingSession.ItemRef] = []
        for i in 0..<100 { refs.append(.init(id: UUID(), name: "I\(i)")) }
        let snap = snapshot([(.fine, refs)])
        let newID = UUID()
        let session = RankingSession(
            snapshot: snap,
            newItemID: newID,
            comparisonCap: 5,
            randomSource: { 0.5 }
        )
        session.selectBucket(.fine)
        for _ in 0..<5 {
            guard case .askingComparison(_, .binarySearch) = session.state else {
                XCTFail("Expected binary search comparison")
                return (session, newID)
            }
            session.answerComparison(winner: newID)
        }
        return (session, newID)
    }

    @MainActor
    func test_capHit_tiesBreakWithRandomMidpoint() {
        let (session, newID) = sessionAtTieBreak()
        guard case .askingComparison(let opp, .tieBreak) = session.state else {
            return XCTFail("Expected tie-break, got \(session.state)")
        }
        XCTAssertEqual(opp.name, "I1")

        // Spec § 4 step four: winning the tie-break places the new item
        // immediately above I1 — between I0 and I1 — not above I0, which it
        // was never compared against. Mid-bucket, so no boundary check.
        session.answerComparison(winner: newID)
        assertFinished(session, bucket: .fine, rank: 1, comparisonCount: 6)
    }

    @MainActor
    func test_capHit_losingTieBreakPlacesImmediatelyBelow() {
        let (session, _) = sessionAtTieBreak()
        guard case .askingComparison(let opp, .tieBreak) = session.state else {
            return XCTFail("Expected tie-break, got \(session.state)")
        }
        session.answerComparison(winner: opp.id)
        assertFinished(session, bucket: .fine, rank: 2, comparisonCount: 6)
    }

    // MARK: Score interpolation

    func test_scoreInterpolation_threeItemsLovedBucket() {
        let bucket = Bucket.loved // 8.0...10.0
        XCTAssertEqual(ScoreInterpolation.score(forRankIndex: 0, bucketCount: 3, bucket: bucket), 10.0, accuracy: 0.001)
        XCTAssertEqual(ScoreInterpolation.score(forRankIndex: 1, bucketCount: 3, bucket: bucket), 9.0, accuracy: 0.001)
        XCTAssertEqual(ScoreInterpolation.score(forRankIndex: 2, bucketCount: 3, bucket: bucket), 8.0, accuracy: 0.001)
    }

    func test_scoreInterpolation_singleItemTakesUpperBound() {
        // Single-item bucket: score = upperBound (we don't display, but value should be sane).
        XCTAssertEqual(ScoreInterpolation.score(forRankIndex: 0, bucketCount: 1, bucket: .liked), 7.9, accuracy: 0.001)
    }

    func test_scoreInterpolation_fineBucketFiveItems() {
        let b = Bucket.fine // 3.0...5.9
        let scores = (0..<5).map { ScoreInterpolation.score(forRankIndex: $0, bucketCount: 5, bucket: b) }
        // Expected: 5.9, 5.175, 4.45, 3.725, 3.0 (linear interpolation across 5 points).
        XCTAssertEqual(scores[0], 5.9, accuracy: 0.001)
        XCTAssertEqual(scores[4], 3.0, accuracy: 0.001)
        XCTAssertEqual(scores[2], 4.45, accuracy: 0.001)
        // Strictly decreasing.
        for i in 1..<scores.count {
            XCTAssertGreaterThan(scores[i - 1], scores[i])
        }
    }
}
