import SwiftUI

/// Top-level screen showing every list the user has, grouped by category.
struct ListsHomeView: View {
    @Environment(Repository.self) private var repository
    @Environment(AuthSession.self) private var auth
    @State private var creatingList = false
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
        .navigationTitle("AnyRank")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creatingList = true
                } label: {
                    Label("New list", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $creatingList) {
            NavigationStack {
                CreateListView()
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
        repository.deleteList(list)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No lists yet", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Create a list to start ranking restaurants, bars, movies, or anything else.")
        } actions: {
            Button {
                creatingList = true
            } label: {
                Text("Create your first list")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var listOfLists: some View {
        List {
            ForEach(Category.allCases) { category in
                let categoryLists = lists.filter { $0.category == category }
                if !categoryLists.isEmpty {
                    Section(category.displayName) {
                        ForEach(categoryLists) { list in
                            NavigationLink(value: list.id) {
                                ListSummaryRow(list: list)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deletingList = list
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    beginRename(list)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
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
                        }
                    }
                }
            }
        }
        .navigationDestination(for: UUID.self) { listID in
            if let list = repository.lists.first(where: { $0.id == listID }) {
                ListDetailView(list: list)
            }
        }
    }
}

private struct ListSummaryRow: View {
    let list: RankList

    var body: some View {
        HStack {
            Image(systemName: list.category.systemIconName)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(list.name)
                Text("\(list.items.count) item\(list.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
