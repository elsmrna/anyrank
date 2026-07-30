import SwiftUI

/// Sheet that re-ranks an existing item. Skips the identify phase; starts
/// at the bucket picker, runs the comparison flow against a snapshot that
/// excludes the item itself, then applies the new placement with
/// `comparisonKindOverride: .rerank`.
struct RerankFlow: View {
    let item: RankItem
    let list: RankList

    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .bucketPick

    private enum Phase {
        case bucketPick
        case comparing(session: RankingSession)
        case finished(placement: RankingSession.Placement)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Re-rank \(item.name)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if canGoBack {
                            Button {
                                back()
                            } label: {
                                Label("Back", systemImage: "chevron.backward")
                            }
                        } else {
                            Button("Cancel") { dismiss() }
                        }
                    }
                }
        }
    }

    /// Rerank has only two active phases: `.bucketPick` (nothing before
    /// it — Cancel dismisses the whole sheet) and `.comparing` (back
    /// returns to `.bucketPick` and discards the in-flight session).
    private var canGoBack: Bool {
        switch phase {
        case .bucketPick, .finished: return false
        case .comparing:             return true
        }
    }

    private func back() {
        if case .comparing = phase {
            phase = .bucketPick
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .bucketPick:
            BucketPickerScreen(itemName: item.name) { bucket in
                let snapshot = RankingApplier.snapshot(of: list, excludingItemID: item.id)
                let session = RankingSession(snapshot: snapshot, newItemID: item.id)
                session.selectBucket(bucket)
                advance(from: session)
            }

        case .comparing(let session):
            ComparisonScreen(
                newItemName: item.name,
                // Same helpers as the initial-add flow so the item being
                // re-ranked looks identical to how it does when adding.
                newItemImageURLString: RankingApplier.comparisonImageURLString(for: item, in: list),
                newItemSecondaryText: RankingApplier.comparisonSecondaryText(for: item, in: list),
                session: session,
                onAnswer: { winner in
                    session.answerComparison(winner: winner)
                    advance(from: session)
                }
            )

        case .finished(let placement):
            AddItemResultScreen(
                stagedName: item.name,
                placement: placement,
                onDone: {
                    apply(placement: placement)
                    dismiss()
                }
            )
        }
    }

    private func advance(from session: RankingSession) {
        if case .finished(let placement) = session.state {
            phase = .finished(placement: placement)
        } else {
            phase = .comparing(session: session)
        }
    }

    private func apply(placement: RankingSession.Placement) {
        RankingApplier.apply(
            placement: placement,
            item: item,
            list: list,
            repository: repository,
            comparisonKindOverride: .rerank
        )
    }
}

#Preview {
    let repo = PreviewSupport.fullRestaurantsRepository()
    let list = repo.lists.first!
    let item = list.itemsSortedByScore().first!
    return RerankFlow(item: item, list: list)
        .environment(repo)
}
