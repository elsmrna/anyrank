import Foundation
import Observation

/// State machine that drives the add-item (or re-rank) flow.
///
/// Lifecycle:
///   1. Caller constructs a `RankingSession` with a list snapshot and the
///      new item's identity.
///   2. Session starts in `.awaitingBucket`.
///   3. View calls `selectBucket(_:)` with the user's sentiment pick. State
///      transitions to `.askingComparison(...)` (or `.finished` if the bucket
///      was empty and no boundary check applies).
///   4. View renders the side-by-side comparison and calls
///      `answerComparison(winner:)`. State advances by one step:
///      another comparison, a boundary check, a tie-break, or `.finished`.
///   5. When `.finished(placement)` is reached, the caller applies the
///      placement to SwiftData via `RankingApplier`.
///
/// All randomness (tie-break index selection) is injected so tests are
/// deterministic. The session is pure: it does not touch SwiftData.
@MainActor
@Observable
final class RankingSession {

    // MARK: Public types

    struct ItemRef: Identifiable, Equatable, Hashable, Sendable {
        let id: UUID
        let name: String
        /// Optional image URL (movie poster, book cover, etc.) — nil for
        /// items without art (places, custom items without a photo).
        /// Rendered as a thumbnail on the comparison card.
        let imageURLString: String?
        /// Optional one-line supporting text — year, author, address.
        /// Helps the user disambiguate similarly-named opponents.
        let secondaryText: String?

        init(id: UUID, name: String, imageURLString: String? = nil, secondaryText: String? = nil) {
            self.id = id
            self.name = name
            self.imageURLString = imageURLString
            self.secondaryText = secondaryText
        }
    }

    /// Snapshot of the list's existing items, organized by bucket and
    /// pre-sorted by score descending within each bucket.
    struct ListSnapshot: Equatable, Sendable {
        let bucketContents: [Bucket: [ItemRef]]

        func items(in bucket: Bucket) -> [ItemRef] {
            bucketContents[bucket] ?? []
        }

        static let empty = ListSnapshot(bucketContents: [:])
    }

    enum State: Equatable {
        /// Show the bucket picker.
        case awaitingBucket
        /// Show the comparison screen. `against` is the existing item to
        /// compare the new item against. `kind` is for analytics/audit.
        case askingComparison(against: ItemRef, kind: ComparisonKind)
        /// Flow complete; apply the placement to storage.
        case finished(Placement)
    }

    struct ProposedRecord: Equatable, Sendable {
        let winnerItemID: UUID
        let loserItemID: UUID
        let kind: ComparisonKind
    }

    struct Placement: Equatable, Sendable {
        /// Final bucket. May differ from the user's pick if the boundary
        /// check promoted or demoted the item.
        let bucket: Bucket
        /// 0-indexed insertion rank within `bucket`. After insertion,
        /// the new item sits at this index in the bucket's score-desc list.
        let rankInBucket: Int
        /// Every comparison performed during the session, in order.
        let comparisons: [ProposedRecord]
    }

    // MARK: Public read-only state

    private(set) var state: State = .awaitingBucket

    /// The number of binary-search comparisons performed so far. Boundary
    /// check and tie-break comparisons are tracked separately and don't
    /// count against the cap.
    private(set) var binarySearchComparisonsUsed: Int = 0

    /// Rough estimate of the total comparisons the user will do this
    /// session. Based on `log2(bucketCount + 1)` for the binary search
    /// plus one for the possible boundary check. Used by the UI to
    /// show "Comparison N of ~M" as a progress hint. Deliberately
    /// approximate — the actual count depends on where the item lands
    /// and whether the boundary check fires.
    var estimatedTotalRounds: Int {
        guard let bucket = pickedBucket else { return 1 }
        let count = snapshot.items(in: bucket).count
        if count == 0 { return 1 }
        let binaryRounds = Int(ceil(log2(Double(count + 1))))
        // +1 to hedge for a possible boundary check. Clamped to at
        // least the count we've already used so the label never says
        // "Comparison 4 of ~3" during a tie-break edge case.
        return max(binaryRounds + 1, binarySearchComparisonsUsed)
    }

    // MARK: Inputs

    private let snapshot: ListSnapshot
    /// The UUID assigned to the not-yet-persisted new item. The view layer
    /// uses this to identify which side of a comparison is "the new one."
    let newItemID: UUID
    private let comparisonCap: Int
    private let randomSource: () -> Double

    // MARK: Internal mutable state

    /// The bucket the user picked. Set on `selectBucket`.
    private var pickedBucket: Bucket?

    /// Binary search bounds within the picked bucket, score-desc indices.
    /// `loIndex` = inclusive lower bound (rank closer to top).
    /// `hiIndex` = exclusive upper bound. Insertion index when lo == hi.
    private var loIndex: Int = 0
    private var hiIndex: Int = 0

    /// Records accumulated across the session.
    private var records: [ProposedRecord] = []

    /// Tracks which phase we're in so `answerComparison` knows what to do
    /// with the answer.
    private enum Phase {
        case binarySearch
        case tieBreak(midIndex: Int)
        case boundaryCheck(direction: BoundaryDirection)
    }
    private var phase: Phase = .binarySearch

    private enum BoundaryDirection { case upward, downward }

    // MARK: Init

    init(
        snapshot: ListSnapshot,
        newItemID: UUID,
        comparisonCap: Int = 5,
        randomSource: @escaping () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.snapshot = snapshot
        self.newItemID = newItemID
        self.comparisonCap = comparisonCap
        self.randomSource = randomSource
    }

    // MARK: Public API

    /// Step 1: user has picked their sentiment bucket.
    /// May complete immediately if the bucket is empty and no boundary
    /// check is applicable; otherwise advances to the first comparison.
    func selectBucket(_ bucket: Bucket) {
        guard case .awaitingBucket = state else { return }
        pickedBucket = bucket

        let bucketItems = snapshot.items(in: bucket)
        loIndex = 0
        hiIndex = bucketItems.count

        if bucketItems.isEmpty {
            // Empty bucket: no within-bucket comparisons possible.
            // Boundary check still runs if an adjacent bucket has items.
            advanceAfterBinarySearchSettled()
        } else {
            phase = .binarySearch
            askNextBinarySearchComparison()
        }
    }

    /// Step 2..N: the user picked one of the two items in the comparison.
    /// `winner` is the UUID of whichever they preferred.
    func answerComparison(winner: UUID) {
        guard case .askingComparison(let against, _) = state else { return }
        let newWon = (winner == newItemID)
        let loserID = newWon ? against.id : newItemID
        let winnerID = newWon ? newItemID : against.id

        switch phase {
        case .binarySearch:
            records.append(.init(
                winnerItemID: winnerID,
                loserItemID: loserID,
                kind: .binarySearch
            ))
            // Find the index that was being compared (it's the midpoint of
            // the previous range). Recompute it the same way as the prompt.
            let mid = (loIndex + hiIndex) / 2
            if newWon {
                // New item is better than items[mid]; insertion point lies
                // somewhere in [lo, mid].
                hiIndex = mid
            } else {
                // New item is worse than items[mid]; insertion lies in
                // (mid, hi).
                loIndex = mid + 1
            }
            askNextBinarySearchComparison()

        case .tieBreak(let midIndex):
            records.append(.init(
                winnerItemID: winnerID,
                loserItemID: loserID,
                kind: .tieBreak
            ))
            // Resolve the unresolved range using the tie-break midpoint.
            if newWon {
                hiIndex = midIndex
            } else {
                loIndex = midIndex + 1
            }
            // Tie-break collapses ambiguity. Move on to boundary check.
            advanceAfterBinarySearchSettled()

        case .boundaryCheck(let direction):
            records.append(.init(
                winnerItemID: winnerID,
                loserItemID: loserID,
                kind: .boundaryCheck
            ))
            applyBoundaryCheckResult(direction: direction, newItemWon: newWon)
        }
    }

    // MARK: Private — binary search loop

    /// Either asks the next bisection comparison, runs the tie-break, or
    /// settles the binary search and proceeds to the boundary-check phase.
    private func askNextBinarySearchComparison() {
        guard let bucket = pickedBucket else { return }
        let bucketItems = snapshot.items(in: bucket)

        if loIndex >= hiIndex {
            // Search converged exactly. Move on.
            advanceAfterBinarySearchSettled()
            return
        }

        if binarySearchComparisonsUsed >= comparisonCap {
            // Cap hit before convergence. Run a tie-break against a random
            // index in the unresolved (lo, hi) range and terminate.
            askTieBreakComparison(bucketItems: bucketItems)
            return
        }

        let mid = (loIndex + hiIndex) / 2
        let opponent = bucketItems[mid]
        binarySearchComparisonsUsed += 1
        phase = .binarySearch
        state = .askingComparison(against: opponent, kind: .binarySearch)
    }

    private func askTieBreakComparison(bucketItems: [ItemRef]) {
        // Pick a random index in [lo, hi). hi is exclusive; if hi - lo == 1
        // there's only one option and the search would have already settled.
        // Defensive math just in case.
        let span = max(hiIndex - loIndex, 1)
        let rawSample = randomSource()
        let offset = min(span - 1, max(0, Int(rawSample * Double(span))))
        let index = loIndex + offset
        let opponent = bucketItems[index]
        phase = .tieBreak(midIndex: index)
        state = .askingComparison(against: opponent, kind: .tieBreak)
    }

    // MARK: Private — boundary check

    /// Called once the binary search (and any tie-break) has settled
    /// `loIndex` to a definite insertion point. Decides whether the
    /// boundary-check comparison applies.
    private func advanceAfterBinarySearchSettled() {
        guard let bucket = pickedBucket else { return }
        let bucketItems = snapshot.items(in: bucket)
        let bucketCount = bucketItems.count
        let position = loIndex // == hiIndex after settling

        // Boundary direction priority:
        //   - If at top (position == 0) and a higher bucket has items, check upward.
        //   - Else if at bottom (position == bucketCount) and a lower bucket has items, check downward.
        //   - Otherwise no boundary check; finish.
        // For an empty bucket (count == 0), position is both top and bottom;
        // we prefer an upward check if possible.

        let atTop = (position == 0)
        let atBottom = (position == bucketCount)

        if atTop, let above = bucket.bucketAbove, !snapshot.items(in: above).isEmpty {
            askBoundaryCheck(direction: .upward, against: snapshot.items(in: above).last!)
            return
        }
        if atBottom, let below = bucket.bucketBelow, !snapshot.items(in: below).isEmpty {
            askBoundaryCheck(direction: .downward, against: snapshot.items(in: below).first!)
            return
        }

        finalize(in: bucket, position: position)
    }

    private func askBoundaryCheck(direction: BoundaryDirection, against opponent: ItemRef) {
        phase = .boundaryCheck(direction: direction)
        state = .askingComparison(against: opponent, kind: .boundaryCheck)
    }

    private func applyBoundaryCheckResult(direction: BoundaryDirection, newItemWon: Bool) {
        guard let bucket = pickedBucket else { return }
        switch direction {
        case .upward:
            // Compared against the bottom of the bucket above.
            // If new item won, promote it: insert at the bottom of bucketAbove.
            // If it lost, stay in the picked bucket at position 0.
            if newItemWon, let above = bucket.bucketAbove {
                let aboveCount = snapshot.items(in: above).count
                finalize(in: above, position: aboveCount)
            } else {
                finalize(in: bucket, position: 0)
            }
        case .downward:
            // Compared against the top of the bucket below.
            // If new item won, stay in the picked bucket at the bottom (position N).
            // If it lost, demote: insert at the top of bucketBelow (position 0).
            if newItemWon {
                let bucketCount = snapshot.items(in: bucket).count
                finalize(in: bucket, position: bucketCount)
            } else if let below = bucket.bucketBelow {
                finalize(in: below, position: 0)
            } else {
                let bucketCount = snapshot.items(in: bucket).count
                finalize(in: bucket, position: bucketCount)
            }
        }
    }

    private func finalize(in bucket: Bucket, position: Int) {
        state = .finished(.init(
            bucket: bucket,
            rankInBucket: position,
            comparisons: records
        ))
    }
}
