import SwiftUI

/// Detail screen for a single list. Items shown in score-desc order with
/// bucket color accents. "+" toolbar button starts the add-item flow.
struct ListDetailView: View {
    let list: RankList

    @Environment(Repository.self) private var repository

    @State private var addingItem = false
    @State private var rerankPromptDismissed = false
    @State private var pendingRerank: PendingRerank?

    private var sortedItems: [RankItem] {
        list.itemsSortedByScore()
    }

    /// Category-appropriate singular noun for the add-item button label.
    /// "Add restaurant" / "Add bar" / "Add movie" / "Add book" reads
    /// more concretely than a generic "Add item".
    private var addItemNoun: String {
        switch list.category {
        case .restaurants: return "restaurant"
        case .bars:        return "bar"
        case .movies:      return "movie"
        case .books:       return "book"
        case .anime:       return "anime"
        case .games:       return "game"
        case .albums:      return "album"
        case .songs:       return "song"
        case .custom:      return "item"
        }
    }

    var body: some View {
        Group {
            if list.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        // Add-item lives in a bottom safe-area inset — always visible,
        // thumb-reachable, and doesn't float over scrolling content the
        // way a FAB would. `safeAreaInset` (vs. `.bottomBar` toolbar)
        // lets us style the button prominently and control padding.
        .safeAreaInset(edge: .bottom) {
            Button {
                addingItem = true
            } label: {
                Label("Add \(addItemNoun)", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .padding(.top, 4)
            .background(.thinMaterial)
        }
        .sheet(isPresented: $addingItem) {
            AddItemFlow(list: list)
        }
        .sheet(item: $pendingRerank) { pending in
            RerankFlow(item: pending.item, list: list)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No items yet", systemImage: list.category.systemIconName)
        } description: {
            Text("Add a \(list.category.displayName.lowercased().dropLast()) to start ranking.")
        } actions: {
            Button("Add the first item") { addingItem = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var itemList: some View {
        List {
            if shouldShowRerankBanner {
                Section {
                    RerankPromptBanner(
                        list: list,
                        onAccept: {
                            if let target = oldestItemForRerank() {
                                pendingRerank = PendingRerank(item: target)
                            }
                            list.additionsSinceLastRerankPrompt = 0
                            repository.touch(list)
                        },
                        onDismiss: {
                            list.additionsSinceLastRerankPrompt = 0
                            repository.touch(list)
                            rerankPromptDismissed = true
                        }
                    )
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            Section {
                ForEach(sortedItems) { item in
                    NavigationLink {
                        ItemDetailView(item: item, list: list)
                    } label: {
                        ItemRow(item: item)
                    }
                }
                .onDelete(perform: deleteItems)
            }
        }
    }

    private var shouldShowRerankBanner: Bool {
        !rerankPromptDismissed
            && list.items.count >= 3
            && list.additionsSinceLastRerankPrompt >= list.rerankPromptThreshold
    }

    private func oldestItemForRerank() -> RankItem? {
        list.items.sorted { $0.createdAt < $1.createdAt }.first
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = sortedItems[index]
            RankingApplier.delete(item: item, from: list, repository: repository)
        }
    }
}

private struct PendingRerank: Identifiable {
    let item: RankItem
    var id: UUID { item.id }
}

#Preview("Full list") {
    let repo = PreviewSupport.fullRestaurantsRepository()
    let list = repo.lists.first!
    return NavigationStack {
        ListDetailView(list: list)
    }
    .environment(repo)
}

#Preview("Single item — no scores yet") {
    let repo = PreviewSupport.singleItemRepository()
    let list = repo.lists.first!
    return NavigationStack {
        ListDetailView(list: list)
    }
    .environment(repo)
}

#Preview("Empty") {
    let repo = PreviewSupport.emptyRepository()
    let list = RankList(name: "New Restaurants", category: .restaurants)
    repo.addList(list)
    return NavigationStack {
        ListDetailView(list: list)
    }
    .environment(repo)
}
