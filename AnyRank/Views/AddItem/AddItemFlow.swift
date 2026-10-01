import SwiftUI

/// Top-level sheet for adding an item. Holds the `AddItemCoordinator` and
/// hands it to `PlacementFlowView`, which pushes each step.
struct AddItemFlow: View {
    let list: RankList

    @Environment(Repository.self) private var repository

    @State private var coordinator: AddItemCoordinator

    init(list: RankList) {
        self.list = list
        _coordinator = State(initialValue: AddItemCoordinator(list: list))
    }

    var body: some View {
        PlacementFlowView(
            coordinator: coordinator,
            rootTitle: "Add to \(list.name)",
            newItemImageURLString: \.artworkURLString,
            newItemSecondaryText: \.secondaryText,
            onCommit: apply(staged:placement:)
        ) {
            ItemSearchScreen(category: list.category, list: list) { staged in
                coordinator.itemIdentified(staged)
            }
        }
    }

    private func apply(staged: StagedItem, placement: RankingSession.Placement) {
        let item = RankItem(
            id: staged.id,
            name: staged.name,
            bucket: placement.bucket
        )
        staged.apply(to: item)
        RankingApplier.apply(
            placement: placement,
            item: item,
            list: list,
            repository: repository
        )
    }
}

#Preview("Empty list — Restaurants") {
    let repo = PreviewSupport.emptyRepository()
    let list = RankList(name: "Restaurants", category: .restaurants)
    repo.addList(list)
    return AddItemFlow(list: list)
        .environment(repo)
}

#Preview("Populated list — Restaurants") {
    let repo = PreviewSupport.fullRestaurantsRepository()
    let list = repo.lists.first!
    return AddItemFlow(list: list)
        .environment(repo)
}
