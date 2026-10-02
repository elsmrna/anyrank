import SwiftUI

/// Detail screen for a single list. Items are shown in score-desc order,
/// sectioned by bucket, with a thumb-reachable add button at the bottom.
struct ListDetailView: View {
    let list: RankList

    @Environment(Repository.self) private var repository
    @Environment(\.importStore) private var importStore
    @Environment(\.router) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var addingItem = false
    @State private var rerankPromptDismissed = false
    @State private var pendingRerank: PendingRerank?

    /// Item briefly highlighted after it's added, so the eye lands on
    /// where it was placed.
    @State private var highlightedItemID: UUID?

    @State private var renaming = false
    @State private var renameDraft = ""
    @State private var confirmingDelete = false

    @State private var importing = false
    @State private var ranking = false
    @State private var confirmingAbandon = false

    private var importSession: ImportSession? {
        importStore.session(for: list.id)
    }

    private var sortedItems: [RankItem] {
        list.itemsSortedByScore()
    }

    var body: some View {
        Group {
            if list.items.isEmpty && importSession == nil {
                emptyState
            } else {
                itemList
            }
        }
        .screenBackground()
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        importing = true
                    } label: {
                        Label("Import into this list…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        renameDraft = list.name
                        renaming = true
                    } label: {
                        Label("Rename list", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete list", systemImage: "trash")
                    }
                } label: {
                    Label("List options", systemImage: "ellipsis")
                }
            }
        }
        // Add-item lives in a bottom safe-area inset — always visible,
        // thumb-reachable, and doesn't cover the last row the way a
        // floating button would.
        .safeAreaInset(edge: .bottom) {
            if !list.items.isEmpty || importSession != nil {
                addButton
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(alignment: .top) {
                        LinearGradient(
                            colors: [Theme.background.opacity(0), Theme.background],
                            startPoint: .top,
                            endPoint: .init(x: 0.5, y: 0.35)
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    }
            }
        }
        .sheet(isPresented: $addingItem) {
            AddItemFlow(list: list)
        }
        .sheet(item: $pendingRerank) { pending in
            RerankFlow(item: pending.item, list: list)
        }
        .sheet(isPresented: $ranking) {
            RankingSpreeView(list: list)
        }
        .sheet(isPresented: $importing) {
            ImportFlowView(targetList: list)
        }
        .confirmationDialog("Abandon this import?", isPresented: $confirmingAbandon, titleVisibility: .visible) {
            Button("Abandon import", role: .destructive) {
                withAnimation(Theme.spring) { importStore.abandon(list.id) }
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            if let importSession {
                Text("The \(importSession.pending.count) you haven't ranked yet won't be added. The \(importSession.rankedCount) you've ranked stay in the list.")
            }
        }
        // An import was just created for this list — start ranking once
        // any sheet that created it has finished dismissing.
        .onAppear(perform: startRequestedSpree)
        // Opening a list counts as using it, for the home screen's Recent sort.
        .onAppear { repository.markUsed(list) }
        .onChange(of: router.spreeRequestListID) { _, _ in startRequestedSpree() }
        .alert("Rename list", isPresented: $renaming) {
            TextField("List name", text: $renameDraft)
                .textInputAutocapitalization(.words)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \"\(list.name)\"?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the list, all its items, and its comparison history.")
        }
        .sensoryFeedback(.success, trigger: highlightedItemID) { _, new in new != nil }
    }

    private func startRequestedSpree() {
        guard router.spreeRequestListID == list.id else { return }
        router.spreeRequestListID = nil
        guard importSession != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            ranking = true
        }
    }

    /// Primary normally; quiet while an import is underway, so the import
    /// card's "Continue ranking" is the one obvious next step.
    @ViewBuilder
    private var addButton: some View {
        let button = Button {
            addingItem = true
        } label: {
            Label("Add \(list.category.itemNoun)", systemImage: "plus")
        }
        if importSession != nil {
            button.buttonStyle(.secondary)
        } else {
            button.buttonStyle(.primary)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            CategoryIconTile(category: list.category, size: 72)
            VStack(spacing: 8) {
                Text("Nothing here yet")
                    .font(.display(.title2))
                    .foregroundStyle(Theme.textPrimary)
                Text("Add your first \(list.category.itemNoun). After that, each new one is placed by comparing it with a few you've already ranked.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            addButton
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 8)
    }

    // MARK: Items

    private var itemList: some View {
        let items = sortedItems
        let rankByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0 + 1) })

        return ScrollViewReader { proxy in
            List {
                if !items.isEmpty {
                    Section {
                        summaryHeader
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                }

                if let importSession {
                    Section {
                        ImportProgressCard(
                            session: importSession,
                            category: list.category,
                            onContinue: { ranking = true },
                            onAbandon: { confirmingAbandon = true }
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

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
                                withAnimation(Theme.spring) { rerankPromptDismissed = true }
                            }
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                ForEach(Bucket.orderedHighToLow) { bucket in
                    let bucketItems = items.filter { $0.bucket == bucket }
                    if !bucketItems.isEmpty {
                        Section {
                            ForEach(bucketItems) { item in
                                NavigationLink {
                                    ItemDetailView(item: item, list: list)
                                } label: {
                                    ItemRow(item: item, rank: rankByID[item.id])
                                }
                                .id(item.id)
                                .listRowBackground(
                                    Theme.surface.overlay(
                                        bucket.color.opacity(highlightedItemID == item.id ? 0.16 : 0)
                                    )
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        pendingRerank = PendingRerank(item: item)
                                    } label: {
                                        Label("Re-rank", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    .tint(Theme.olive)
                                }
                            }
                        } header: {
                            BucketSectionHeader(bucket: bucket, count: bucketItems.count)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .themedList()
            .onChange(of: list.items.count) { old, new in
                // During a spree the sheet covers the list; don't scroll or
                // buzz behind it for every placement.
                guard !ranking, new > old, let newest = list.items.max(by: { $0.createdAt < $1.createdAt }) else { return }
                revealNewItem(newest.id, proxy: proxy)
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: list.category.systemIconName)
                Text("\(list.items.count) \(list.items.count == 1 ? list.category.itemNoun : pluralNoun)")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            BucketDistributionBar(counts: list.bucketCounts, height: 8)
        }
        .padding(.vertical, 4)
    }

    private var pluralNoun: String {
        switch list.category {
        case .anime:  return "anime"
        case .custom: return "items"
        default:      return list.category.itemNoun + "s"
        }
    }

    private func revealNewItem(_ id: UUID, proxy: ScrollViewProxy) {
        Task { @MainActor in
            // Let the sheet finish dismissing before moving the list.
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(Theme.spring) {
                proxy.scrollTo(id, anchor: .center)
                highlightedItemID = id
            }
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.easeOut(duration: 0.6)) {
                if highlightedItemID == id { highlightedItemID = nil }
            }
        }
    }

    private var shouldShowRerankBanner: Bool {
        importSession == nil
            && !rerankPromptDismissed
            && list.items.count >= 3
            && list.additionsSinceLastRerankPrompt >= list.rerankPromptThreshold
    }

    private func oldestItemForRerank() -> RankItem? {
        list.items.sorted { $0.createdAt < $1.createdAt }.first
    }

    private func delete(_ item: RankItem) {
        withAnimation(Theme.spring) {
            RankingApplier.delete(item: item, from: list, repository: repository)
        }
    }

    private func commitRename() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != list.name else { return }
        list.name = trimmed
        repository.touch(list)
    }

    private func commitDelete() {
        importStore.abandon(list.id)
        dismiss()
        // Delete once the pop has finished so this screen doesn't blank
        // out mid-transition; the home card then animates away.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(Theme.spring) {
                repository.deleteList(list)
            }
        }
    }
}

private struct BucketSectionHeader: View {
    let bucket: Bucket
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: bucket.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(bucket.color)
            Text(bucket.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(count)")
                .font(.score(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .textCase(nil)
        .padding(.leading, -4)
        .accessibilityElement(children: .combine)
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
