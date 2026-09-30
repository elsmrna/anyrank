import SwiftUI

/// Shared chrome for the add-item and re-rank sheets. Each step of the
/// coordinator is a real navigation push, so the back button and edge
/// swipe both work and step the state machine back. The result screen
/// fades in over the top once placement is final.
struct PlacementFlowView<Root: View>: View {
    let coordinator: AddItemCoordinator
    let rootTitle: String
    /// Artwork / secondary text for the item being placed.
    let newItemImageURLString: (StagedItem) -> String?
    let newItemSecondaryText: (StagedItem) -> String?
    /// Persist the final placement. Called exactly once.
    let onCommit: (StagedItem, RankingSession.Placement) -> Void
    @ViewBuilder let root: () -> Root

    @Environment(\.dismiss) private var dismiss
    @State private var committed = false

    var body: some View {
        ZStack {
            NavigationStack(path: pathBinding) {
                root()
                    .screenBackground()
                    .navigationTitle(rootTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
                    .navigationDestination(for: AddItemCoordinator.Step.self) { step in
                        destination(for: step)
                            .screenBackground()
                            .navigationBarTitleDisplayMode(.inline)
                    }
            }

            if case .finished(let staged, let placement) = coordinator.phase {
                AddItemResultScreen(stagedName: staged.name, placement: placement) {
                    commit(staged: staged, placement: placement)
                }
                .screenBackground()
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.isFinished)
        .interactiveDismissDisabled(coordinator.isFinished)
        .presentationBackground(Theme.background)
        .presentationCornerRadius(28)
    }

    private var pathBinding: Binding<[AddItemCoordinator.Step]> {
        Binding(
            get: { coordinator.path },
            set: { coordinator.path = $0 }
        )
    }

    @ViewBuilder
    private func destination(for step: AddItemCoordinator.Step) -> some View {
        switch step {
        case .bucketPick:
            BucketPickerScreen(itemName: coordinator.staged?.name ?? "") { bucket in
                coordinator.bucketPicked(bucket)
            }
        case .comparing:
            if let staged = coordinator.staged, let session = coordinator.session {
                ComparisonScreen(
                    newItemName: staged.name,
                    newItemImageURLString: newItemImageURLString(staged),
                    newItemSecondaryText: newItemSecondaryText(staged),
                    category: coordinator.list.category,
                    session: session,
                    onAnswer: { winner in coordinator.answer(winner: winner) }
                )
            }
        }
    }

    private func commit(staged: StagedItem, placement: RankingSession.Placement) {
        // The result screen can fire both from its timer and a tap.
        guard !committed else { return }
        committed = true
        onCommit(staged, placement)
        dismiss()
    }
}
