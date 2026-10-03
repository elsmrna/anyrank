import SwiftUI

/// Top-level screen showing every list the user has, sorted by recent use,
/// type, or name.
struct ListsHomeView: View {
    @Environment(Repository.self) private var repository
    @Environment(AuthSession.self) private var auth
    @Environment(\.importStore) private var importStore
    @State private var importing = false
    @State private var creatingList: CreateListRequest?
    @State private var showingSettings = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("homeSortOrder") private var sortOrder: ListSort.Order = .recent
    @AppStorage("homeSortReversed") private var sortReversed = false

    private var sort: ListSort { ListSort(order: sortOrder, reversed: sortReversed) }

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
                    Menu {
                        Button {
                            creatingList = CreateListRequest()
                        } label: {
                            Label("New list", systemImage: "plus")
                        }
                        Button {
                            importing = true
                        } label: {
                            Label("Import a collection", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    } primaryAction: {
                        creatingList = CreateListRequest()
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
        .sheet(isPresented: $importing) {
            ImportFlowView()
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
        importStore.abandon(list.id)
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

                VStack(spacing: 10) {
                    Button("Create a list") {
                        creatingList = CreateListRequest()
                    }
                    .buttonStyle(.primary)
                    Button("Import from Steam, Letterboxd…") {
                        importing = true
                    }
                    .buttonStyle(.secondary)
                }
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

                sortControls
                    .padding(.bottom, 4)

                ForEach(sort.sections(lists), id: \.category) { section in
                    if let category = section.category {
                        SectionLabel(category.displayName)
                            .padding(.top, 12)
                            .padding(.leading, 4)
                    }
                    ForEach(section.lists) { list in
                        listRow(list)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
    }

    private func listRow(_ list: RankList) -> some View {
        NavigationLink(value: list.id) {
            ListCard(
                list: list,
                pendingImportCount: importStore.session(for: list.id)?.pending.count,
                importSource: importStore.session(for: list.id)?.source
            )
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

    // MARK: Sorting

    /// "Sort by" menu plus a direction toggle, under the summary line.
    private var sortControls: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Sort by", selection: sortOrderBinding) {
                    ForEach(ListSort.Order.allCases) { order in
                        Label(order.title, systemImage: order.systemImage).tag(order)
                    }
                }
            } label: {
                SortChip(systemImage: sort.order.systemImage, title: sort.order.title, showsChevron: true)
            }
            .accessibilityLabel("Sort by \(sort.order.title)")

            Button {
                withAnimation(Theme.spring) { sortReversed.toggle() }
            } label: {
                SortChip(systemImage: "arrow.up.arrow.down", title: sort.directionTitle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Order: \(sort.directionTitle)")
            .accessibilityHint("Reverses the order")

            Spacer()
        }
        .sensoryFeedback(.selection, trigger: sort)
    }

    /// Changing what to sort by starts from that sort's natural direction.
    private var sortOrderBinding: Binding<ListSort.Order> {
        Binding(get: { sortOrder }, set: { newValue in
            withAnimation(Theme.spring) {
                sortOrder = newValue
                sortReversed = false
            }
        })
    }

    private var summaryLine: String {
        let itemCount = lists.reduce(0) { $0 + $1.items.count }
        let listPart = "\(lists.count) list\(lists.count == 1 ? "" : "s")"
        let itemPart = "\(itemCount) thing\(itemCount == 1 ? "" : "s") ranked"
        return "\(listPart) · \(itemPart)"
    }
}

/// Small capsule used by the home screen's sort controls.
private struct SortChip: View {
    let systemImage: String
    let title: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.medium))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        .contentShape(Capsule())
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
    /// Items still waiting in this list's import, if one is underway.
    var pendingImportCount: Int? = nil
    var importSource: ImportSourceKind? = nil

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
            if let pendingImportCount {
                HStack(spacing: 6) {
                    if let brand = importSource.flatMap(ServiceBrand.init) {
                        BrandIcon(brand: brand, size: 16)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text("\(pendingImportCount) to rank")
                }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    /// Only fan out covers when there's real art; a row of placeholders
    /// is just noise. Place lists are left out: a place photo may not
    /// exist (or no Places key is set), so they could be all placeholders.
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
