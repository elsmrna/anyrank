import Foundation
import Observation

/// State machine for the add-item sheet. Drives the four phases of the flow:
///   1. Identifying the item (search or custom form)
///   2. Bucket pick
///   3. Comparison loop (delegated to `RankingSession`)
///   4. Result confirmation
///
/// The coordinator is `@Observable` so the SwiftUI sheet re-renders as the
/// phase changes. Application to SwiftData is performed by the view at the
/// end via `RankingApplier` — the coordinator itself stays storage-agnostic.
@MainActor
@Observable
final class AddItemCoordinator {
    enum Phase {
        case identifying
        case bucketPick(staged: StagedItem)
        case comparing(staged: StagedItem, session: RankingSession)
        case finished(staged: StagedItem, placement: RankingSession.Placement)
    }

    var phase: Phase = .identifying

    let list: RankList
    let snapshotProvider: () -> RankingSession.ListSnapshot

    init(
        list: RankList,
        snapshotProvider: (() -> RankingSession.ListSnapshot)? = nil
    ) {
        self.list = list
        self.snapshotProvider = snapshotProvider ?? { RankingApplier.snapshot(of: list) }
    }

    func itemIdentified(_ staged: StagedItem) {
        phase = .bucketPick(staged: staged)
    }

    func bucketPicked(_ bucket: Bucket) {
        guard case .bucketPick(let staged) = phase else { return }
        let session = RankingSession(snapshot: snapshotProvider(), newItemID: staged.id)
        session.selectBucket(bucket)
        phase = .comparing(staged: staged, session: session)
        promoteToFinishedIfNeeded()
    }

    func answer(winner: UUID) {
        guard case .comparing(_, let session) = phase else { return }
        session.answerComparison(winner: winner)
        promoteToFinishedIfNeeded()
    }

    /// Step back one phase. `.comparing` reverts to `.bucketPick` (which
    /// throws away the in-flight `RankingSession` — a new one is built
    /// when the user picks a bucket again). `.bucketPick` reverts to
    /// `.identifying` (letting the user search for a different item).
    /// `.identifying` and `.finished` do nothing — the former is where
    /// the flow starts, the latter auto-dismisses.
    ///
    /// Returns `true` if a step back happened, `false` if there was
    /// nowhere to go — lets the view fall through to Cancel/dismiss
    /// in that case.
    @discardableResult
    func back() -> Bool {
        switch phase {
        case .identifying, .finished:
            return false
        case .bucketPick:
            phase = .identifying
            return true
        case .comparing(let staged, _):
            phase = .bucketPick(staged: staged)
            return true
        }
    }

    /// Whether the current phase has an earlier phase to return to.
    /// Views bind their toolbar to this to swap Cancel for a back chevron.
    var canGoBack: Bool {
        switch phase {
        case .identifying, .finished: return false
        case .bucketPick, .comparing: return true
        }
    }

    /// If the active session has reached `.finished`, hoist its placement
    /// into the coordinator's phase so the view advances.
    private func promoteToFinishedIfNeeded() {
        guard case .comparing(let staged, let session) = phase else { return }
        if case .finished(let placement) = session.state {
            phase = .finished(staged: staged, placement: placement)
        }
    }
}
