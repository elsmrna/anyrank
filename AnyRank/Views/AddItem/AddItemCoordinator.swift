import Foundation
import Observation

/// State machine for the add-item and re-rank sheets. Drives the four
/// phases of the flow:
///   1. Identifying the item (search or custom form) — skipped for re-rank
///   2. Bucket pick
///   3. Comparison loop (delegated to `RankingSession`)
///   4. Result confirmation
///
/// The coordinator is `@Observable` so the sheet re-renders as the phase
/// changes. It also exposes the phase as a `NavigationStack` path, so each
/// step is a real push — native transitions and swipe-to-go-back for free.
/// Application to storage is performed by the view at the end via
/// `RankingApplier`; the coordinator itself stays storage-agnostic.
@MainActor
@Observable
final class AddItemCoordinator {
    enum Phase {
        case identifying
        case bucketPick(staged: StagedItem)
        case comparing(staged: StagedItem, session: RankingSession)
        case finished(staged: StagedItem, placement: RankingSession.Placement)
    }

    /// Screens pushed on top of the flow's root screen. The root is the
    /// item search for adds, and the bucket picker for re-ranks.
    enum Step: Hashable {
        case bucketPick
        case comparing
    }

    private(set) var phase: Phase = .identifying {
        didSet {
            switch phase {
            case .identifying: break
            case .bucketPick(let staged), .finished(let staged, _):
                self.staged = staged
            case .comparing(let staged, let session):
                self.staged = staged
                self.session = session
            }
        }
    }

    /// Most recent staged item and session. Pushed screens read these
    /// rather than `phase` so they keep rendering correctly while they
    /// animate off-screen after a step back.
    private(set) var staged: StagedItem?
    private(set) var session: RankingSession?

    let list: RankList
    let snapshotProvider: () -> RankingSession.ListSnapshot

    /// Re-rank flows start at bucket pick; there's nothing to identify.
    let isRerank: Bool

    init(
        list: RankList,
        snapshotProvider: (() -> RankingSession.ListSnapshot)? = nil
    ) {
        self.list = list
        self.snapshotProvider = snapshotProvider ?? { RankingApplier.snapshot(of: list) }
        self.isRerank = false
    }

    /// Re-rank an existing item: the comparison snapshot excludes the item
    /// itself, and the staged record reuses its ID so the placement applies
    /// back onto it.
    init(rerank item: RankItem, in list: RankList) {
        self.list = list
        self.snapshotProvider = { RankingApplier.snapshot(of: list, excludingItemID: item.id) }
        self.isRerank = true
        let staged = StagedItem(id: item.id, name: item.name, category: list.category)
        self.phase = .bucketPick(staged: staged)
        self.staged = staged
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
    /// `.identifying` for adds. `.identifying` and `.finished` do nothing.
    ///
    /// Returns `true` if a step back happened.
    @discardableResult
    func back() -> Bool {
        switch phase {
        case .identifying, .finished:
            return false
        case .bucketPick:
            guard !isRerank else { return false }
            phase = .identifying
            return true
        case .comparing(let staged, _):
            phase = .bucketPick(staged: staged)
            return true
        }
    }

    /// Whether the current phase has an earlier phase to return to.
    var canGoBack: Bool {
        switch phase {
        case .identifying, .finished: return false
        case .bucketPick:             return !isRerank
        case .comparing:              return true
        }
    }

    var isFinished: Bool {
        if case .finished = phase { return true }
        return false
    }

    /// The phase expressed as a navigation path. Setting a shorter path
    /// (back button, edge swipe) steps the state machine back to match.
    var path: [Step] {
        get {
            let pushed: [Step]
            switch phase {
            case .identifying:
                pushed = []
            case .bucketPick:
                pushed = [.bucketPick]
            case .comparing:
                pushed = [.bucketPick, .comparing]
            case .finished(_, let placement):
                // The result overlays whichever screen finished the flow;
                // comparisons only happened if the comparison screen showed.
                pushed = placement.comparisons.isEmpty ? [.bucketPick] : [.bucketPick, .comparing]
            }
            // Re-rank's root screen *is* the bucket picker.
            return isRerank ? Array(pushed.dropFirst()) : pushed
        }
        set {
            while newValue.count < path.count, back() {}
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
