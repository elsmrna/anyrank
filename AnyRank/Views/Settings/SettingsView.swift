import SwiftUI

/// Settings sheet. Exposes account + sync controls. Sync is opt-in and
/// available only to signed-in users — local-only mode is the default.
struct SettingsView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    accountSection
                    syncSection
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
            } header: {
                Text("Sync")
            } footer: {
                Text("Each list is backed up as a tab in a Google Sheet named \"AnyRank Data\" in your Drive. The app is the source of truth — edits made directly in the Sheet get overwritten.")
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
        .environment(AuthSession.previewSignedOut())
        .environment(SyncCoordinator.preview())
}

#Preview("Signed in, sync off") {
    SettingsView()
        .environment(AuthSession.previewSignedIn())
        .environment(SyncCoordinator.preview())
}

#Preview("Signed in, sync on") {
    SettingsView()
        .environment(AuthSession.previewSignedIn())
        .environment(SyncCoordinator.preview(status: .ready(spreadsheetID: "abc123", lastSyncedAt: Date(timeIntervalSinceNow: -120))))
}
