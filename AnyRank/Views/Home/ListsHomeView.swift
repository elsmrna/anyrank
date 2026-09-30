import SwiftUI

/// Top-level screen showing every list the user has, grouped by category.
struct ListsHomeView: View {
    @Environment(Repository.self) private var repository
    @Environment(AuthSession.self) private var auth
    @State private var creatingList: CreateListRequest?
    @State private var showingSettings = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    /// Rename dialog state. `renamingList` is the list being edited (nil
    /// when the dialog isn't showing); `renameDraft` is the working value
    /// the alert's TextField binds to.
    @State private var renamingList: RankList?
    @State private var renameDraft: String = ""

    /// Delete confirmation state. Same pattern as rename.
    @State private var deletingList: RankList?

    private var lists: [RankList] {
        repository.lists
    }

    var body: some View {
        Group {
            if lists.isEmpty {
                emptyState
            } else {
                listOfLists
            }
        }
        .screenBackground()
        .navigationTitle(lists.isEmpty ? "" : "Your lists")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            if !lists.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creatingList = CreateListRequest()
                    } label: {
                        Label("New list", systemImage: "plus")
                    }
                }
            }
        }
        .navigationDestination(for: UUID.self) { listID in
            if let list = repository.lists.first(where: { $0.id == listID }) {
                ListDetailView(list: list)
            }
        }
        .sheet(item: $creatingList) { request in
            NavigationStack {
                CreateListView(initialCategory: request.category)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: .constant(!hasCompletedOnboarding)) {
            SignInOnboardingView()
        }
        // Rename alert. iOS 16+ supports TextField inside .alert, which is
        // the least-intrusive way to grab a new string. Persist on Save;
        // touch the repository so storage rewrites the CSV and (if sync
        // is on) the coordinator pushes.
        .alert("Rename list", isPresented: renameAlertBinding) {
            TextField("List name", text: $renameDraft)
                .textInputAutocapitalization(.words)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renamingList = nil }
        } message: {
            Text("Give this list a new name.")
        }
        .confirmationDialog(
            deletingList.map { "Delete \"\($0.name)\"?" } ?? "Delete list?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { deletingList = nil }
        } message: {
            Text("This removes the list, all its items, and its comparison history. If Sheets sync is on, the corresponding tabs are removed too.")
        }
    }

    // MARK: Rename / delete helpers

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingList != nil },
            set: { if !$0 { renamingList = nil } }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletingList != nil },
            set: { if !$0 { deletingList = nil } }
        )
    }

    private func beginRename(_ list: RankList) {
        renameDraft = list.name
        renamingList = list
    }

    private func commitRename() {
        guard let list = renamingList else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        renamingList = nil
        guard !trimmed.isEmpty, trimmed != list.name else { return }
        list.name = trimmed
        repository.touch(list)
    }

    private func commitDelete() {
        guard let list = deletingList else { return }
        deletingList = nil
        withAnimation(Theme.spring) {
            repository.deleteList(list)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    ZStack {
                        CategoryIconTile(category: .movies, size: 56)
                            .rotationEffect(.degrees(-10))
                            .offset(x: -46, y: 8)
                        CategoryIconTile(category: .books, size: 56)
                            .rotationEffect(.degrees(10))
                            .offset(x: 46, y: 8)
                        CategoryIconTile(category: .restaurants, size: 68)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .frame(height: 96)
                    .padding(.bottom, 8)

                    Text("Rank anything")
                        .font(.display(.largeTitle))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Skip the star ratings. Compare things two at a time and AnyRank builds your list for you.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Start with")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(Category.allCases) { category in
                            Button {
                                creatingList = CreateListRequest(category: category)
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: category.systemIconName)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(category.tint)
                                    Text(category.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 80)
                                .card(cornerRadius: 16)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }

                Button("Create a list") {
                    creatingList = CreateListRequest()
                }
                .buttonStyle(.primary)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Lists

    private var listOfLists: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 8)

                ForEach(Category.allCases) { category in
                    let categoryLists = lists.filter { $0.category == category }
                    if !categoryLists.isEmpty {
                        SectionLabel(category.displayName)
                            .padding(.top, 12)
                            .padding(.leading, 4)
                        ForEach(categoryLists) { list in
                            NavigationLink(value: list.id) {
                                ListCard(list: list)
                            }
                            .buttonStyle(.pressable)
                            .contextMenu {
                                Button {
                                    beginRename(list)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deletingList = list
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
    }

    private var summaryLine: String {
        let itemCount = lists.reduce(0) { $0 + $1.items.count }
        let listPart = "\(lists.count) list\(lists.count == 1 ? "" : "s")"
        let itemPart = "\(itemCount) thing\(itemCount == 1 ? "" : "s") ranked"
        return "\(listPart) · \(itemPart)"
    }
}

/// Identifiable wrapper so the create sheet can open pre-seeded with a
/// category (from the empty-state shortcuts) or with the default.
struct CreateListRequest: Identifiable {
    let id = UUID()
    var category: Category = .restaurants
}

private struct ListCard: View {
    let list: RankList

    private var topItems: [RankItem] {
        Array(list.itemsSortedByScore().prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                CategoryIconTile(category: list.category)
                VStack(alignment: .leading, spacing: 3) {
                    Text(list.name)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(detailLine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if hasCoverArt {
                    coverStack
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            if !list.items.isEmpty {
                BucketDistributionBar(counts: list.bucketCounts)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    /// Only fan out covers when there's real art; a row of placeholders
    /// is just noise.
    private var hasCoverArt: Bool {
        list.category.hasArtwork
            && topItems.contains { RankingApplier.comparisonImageURLString(for: $0, in: list) != nil }
    }

    private var detailLine: String {
        let count = list.items.count
        guard let top = topItems.first else { return "Nothing ranked yet" }
        return "\(count) \(count == 1 ? "item" : "items") · #1 \(top.name)"
    }

    /// Top three covers fanned out, #1 in front.
    private var coverStack: some View {
        HStack(spacing: -14) {
            ForEach(Array(topItems.enumerated()), id: \.element.id) { index, item in
                ArtworkView(
                    urlString: RankingApplier.comparisonImageURLString(for: item, in: list),
                    category: list.category,
                    width: 30,
                    cornerRadius: 5
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.surface, lineWidth: 1.5)
                )
                .zIndex(Double(3 - index))
            }
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        ListsHomeView()
    }
    .environment(PreviewSupport.emptyRepository())
    .environment(AuthSession.previewSignedOut())
    .environment(SyncCoordinator.preview())
}

#Preview("Multiple lists") {
    NavigationStack {
        ListsHomeView()
    }
    .environment(PreviewSupport.multipleListsRepository())
    .environment(AuthSession.previewSignedIn())
    .environment(SyncCoordinator.preview())
}
