import SwiftUI
import UniformTypeIdentifiers

/// Settings sheet. Exposes account + sync controls, plus export/restore of
/// every list. Sync is opt-in and available only to signed-in users —
/// local-only mode is the default.
struct SettingsView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(SyncCoordinator.self) private var sync
    @Environment(Repository.self) private var repository
    @Environment(\.importStore) private var importStore
    @Environment(\.dismiss) private var dismiss

    /// The export zip, built when Settings opens (lists can't change while
    /// it's up) so the share button is ready to tap.
    @State private var exportURL: URL?
    @State private var choosingRestoreFile = false
    @State private var pendingRestore: [RankList]?
    @State private var restoreMessage: String?
    @State private var restoreError: String?
    @AppStorage(LocationProvider.useOnMapsKey) private var useLocationOnMaps = true

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    accountSection
                    syncSection
                    dataSection
                    mapsSection
                    aboutSection
                }
                .listRowBackground(Theme.surface)
            }
            .themedList()
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationBackground(Theme.background)
        .task(id: repository.lists.count) {
            exportURL = repository.lists.isEmpty ? nil : try? await ListArchive.export(repository.lists)
        }
        .fileImporter(isPresented: $choosingRestoreFile, allowedContentTypes: [.zip]) { result in
            Task { await readRestoreFile(result) }
        }
        .confirmationDialog(
            "Replace your lists?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible,
            presenting: pendingRestore
        ) { lists in
            Button("Restore \(lists.count) \(lists.count == 1 ? "list" : "lists")", role: .destructive) {
                restore(lists)
            }
            Button("Cancel", role: .cancel) {}
        } message: { lists in
            Text(restoreWarning(for: lists))
        }
        .alert(
            "Couldn't restore",
            isPresented: Binding(get: { restoreError != nil }, set: { if !$0 { restoreError = nil } }),
            presenting: restoreError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let user = auth.signedInUser {
                AccountRow(user: user)
                Button("Sign out") {
                    sync.disableSync()
                    auth.signOut()
                }
                .foregroundStyle(Theme.danger)
            } else {
                Button {
                    Task { await auth.signIn() }
                } label: {
                    HStack {
                        if auth.isSigningIn {
                            ProgressView()
                        } else {
                            Image(systemName: "person.crop.circle")
                        }
                        Text(auth.isSigningIn ? "Signing in…" : "Sign in with Google")
                    }
                }
                .disabled(auth.isSigningIn)

                if let error = auth.lastError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
        } header: {
            Text("Account")
        } footer: {
            if auth.signedInUser == nil {
                Text("AnyRank works fully offline. Sign in only if you want cloud sync.")
            }
        }
    }

    // MARK: Sync

    @ViewBuilder
    private var syncSection: some View {
        if auth.signedInUser != nil {
            Section {
                Toggle("Sync to Google Sheets", isOn: syncEnabledBinding)
                    .disabled(syncToggleDisabled)

                switch sync.status {
                case .syncing:
                    HStack {
                        ProgressView()
                        Text("Syncing…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                case .ready(_, let lastSyncedAt):
                    if let lastSyncedAt {
                        LabeledContent("Last synced") {
                            Text(lastSyncedAt, format: .relative(presentation: .named))
                                .font(.caption)
                        }
                    } else {
                        Text("Sync enabled. Changes will push automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .error(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                case .disabled:
                    EmptyView()
                }

                if let restored = sync.restoredListCount {
                    Label(
                        "Found your backup and restored \(restored) \(restored == 1 ? "list" : "lists").",
                        systemImage: "checkmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Each list is backed up as a tab in a Google Sheet named \"AnyRank Data\" in your Drive. If you've synced before, turning this on brings back any lists that aren't on this device. The app is the source of truth — edits made directly in the Sheet get overwritten.")
            }
        }
    }

    private var syncToggleDisabled: Bool {
        if case .syncing = sync.status { return true }
        return false
    }

    private var syncEnabledBinding: Binding<Bool> {
        Binding(
            get: { sync.status.isEnabled },
            set: { newValue in
                Task {
                    if newValue {
                        await sync.enableSync()
                    } else {
                        sync.disableSync()
                    }
                }
            }
        )
    }

    // MARK: Your data

    private var dataSection: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export lists", systemImage: "square.and.arrow.up")
                }
            } else {
                Label("Export lists", systemImage: "square.and.arrow.up")
                    .foregroundStyle(Theme.textTertiary)
            }
            Button {
                choosingRestoreFile = true
            } label: {
                Label("Restore from export…", systemImage: "arrow.counterclockwise")
            }
            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Exports a .zip with every list as a spreadsheet file. Keep it in Files or send it to yourself, and restore it here on any device.")
        }
    }

    private func readRestoreFile(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let lists = try await ListArchive.lists(fromArchive: Data(contentsOf: url))
            if repository.lists.isEmpty {
                restore(lists)
            } else {
                pendingRestore = lists
            }
        } catch {
            restoreError = error.localizedDescription
        }
    }

    private func restoreWarning(for lists: [RankList]) -> String {
        let current = repository.lists.count
        let items = lists.reduce(0) { $0 + $1.items.count }
        return "This replaces your \(current) current \(current == 1 ? "list" : "lists") with the \(lists.count) in this export (\(items) \(items == 1 ? "item" : "items")). It can't be undone, so export first if you want to keep what's here."
    }

    private func restore(_ lists: [RankList]) {
        repository.replaceLists(lists, notifySync: true)
        importStore.prune(keeping: Set(lists.map(\.id)))
        Task { exportURL = try? await ListArchive.export(lists) }
        restoreMessage = "Restored \(lists.count) \(lists.count == 1 ? "list" : "lists")."
    }

    // MARK: Maps

    private var mapsSection: some View {
        Section {
            Toggle("Show my location on maps", isOn: $useLocationOnMaps)
        } header: {
            Text("Maps")
        } footer: {
            Text("When something on a list is within 5 miles, its map opens centered on you. Your location stays on this device.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
        }
    }
}

private struct AccountRow: View {
    let user: SignedInUser

    var body: some View {
        HStack(spacing: 12) {
            avatar
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.body.weight(.semibold))
                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = user.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
            .clipShape(Circle())
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .foregroundStyle(Theme.textTertiary)
    }
}

#Preview("Signed out") {
    SettingsView()
        .environment(PreviewSupport.multipleListsRepository())
        .environment(AuthSession.previewSignedOut())
        .environment(SyncCoordinator.preview())
}

#Preview("Signed in, sync off") {
    SettingsView()
        .environment(PreviewSupport.multipleListsRepository())
        .environment(AuthSession.previewSignedIn())
        .environment(SyncCoordinator.preview())
}

#Preview("Signed in, sync on") {
    SettingsView()
        .environment(PreviewSupport.multipleListsRepository())
        .environment(AuthSession.previewSignedIn())
        .environment(SyncCoordinator.preview(status: .ready(spreadsheetID: "abc123", lastSyncedAt: Date(timeIntervalSinceNow: -120))))
}
