import SwiftUI

/// Sheet that re-ranks an existing item. Starts at the bucket picker,
/// runs the comparison flow against a snapshot that excludes the item
/// itself, then applies the new placement with
/// `comparisonKindOverride: .rerank`.
struct RerankFlow: View {
    let item: RankItem
    let list: RankList

    @Environment(Repository.self) private var repository

    @State private var coordinator: AddItemCoordinator

    init(item: RankItem, list: RankList) {
        self.item = item
        self.list = list
        _coordinator = State(initialValue: AddItemCoordinator(rerank: item, in: list))
    }

    var body: some View {
        PlacementFlowView(
            coordinator: coordinator,
            rootTitle: "Re-rank",
            // Same helpers as the list and detail views so the item being
            // re-ranked looks identical everywhere.
            newItemImageURLString: { _ in RankingApplier.comparisonImageURLString(for: item, in: list) },
            newItemSecondaryText: { _ in RankingApplier.comparisonSecondaryText(for: item, in: list) },
            onCommit: { _, placement in apply(placement: placement) }
        ) {
            BucketPickerScreen(itemName: item.name) { bucket in
                coordinator.bucketPicked(bucket)
            }
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
