import Foundation
import Observation

/// Coordinates between the local Repository and the Google Sheets backing
/// store. Implements `SyncObserver` so the repository can call into it
/// after persistence completes.
///
/// Status: scaffold. The full push/pull/conflict-resolution implementation
/// lives in `pushChanges()` / `pullChanges()` below — see those for details.
/// Until the user enables sync in Settings (which triggers the additional
/// OAuth scopes), the coordinator stays in `.disabled` state and is a no-op.
@MainActor
@Observable
final class SyncCoordinator: SyncObserver {

    enum Status: Equatable {
        case disabled
        case ready(spreadsheetID: String, lastSyncedAt: Date?)
        case syncing
        case error(String)

        var isEnabled: Bool {
            switch self {
            case .disabled: return false
            default: return true
            }
        }
    }

    private(set) var status: Status = .disabled

    /// How many lists were brought back from an existing Sheet the last time
    /// sync was turned on. Settings uses it to confirm the restore.
    private(set) var restoredListCount: Int?

    /// Title of the backing spreadsheet. Also how `connectSpreadsheet` finds
    /// an existing backup when no spreadsheet ID is saved on this device.
    static let spreadsheetTitle = "AnyRank Data"

    private weak var repository: Repository?
    private let auth: AuthSession
    private let sheetsClient: GoogleSheetsClient

    /// Stored spreadsheet ID for this user. Persists across launches via
    /// `UserDefaults` keyed by the user's email.
    private var spreadsheetID: String? {
        didSet { persistSpreadsheetID() }
    }

    /// Debounce buffer for change events. Coalesces rapid edits to the same
    /// list into a single push.
    private var pendingPushIDs: Set<UUID> = []
    private var pushTask: Task<Void, Never>?

    init(repository: Repository, auth: AuthSession, sheetsClient: GoogleSheetsClient = GoogleSheetsClient()) {
        self.repository = repository
        self.auth = auth
        self.sheetsClient = sheetsClient
    }

    // MARK: Bootstrap

    /// Called from `AnyRankApp.task`. If the user is signed in AND has
    /// previously enabled sync, restore the saved spreadsheet ID and
    /// transition to `.ready`. Does not push or pull — that happens on the
    /// first user-driven change or app foreground.
    func bootstrapIfReady() async {
        guard auth.signedInUser != nil else {
            status = .disabled
            return
        }
        if let savedID = restoreSpreadsheetID() {
            spreadsheetID = savedID
            status = .ready(spreadsheetID: savedID, lastSyncedAt: nil)
            // Try a pull on launch — it's a no-op unless the local store
            // is empty (fresh install / reinstall / wiped storage). In
            // the steady-state case local is authoritative and this
            // returns immediately.
            await pullChanges()
        } else {
            status = .disabled
        }
    }

    // MARK: Enable / disable from Settings

    /// User flipped the sync toggle on. Requests Drive/Sheets scopes if
    /// needed, then connects to the backing spreadsheet.
    func enableSync() async {
        status = .syncing
        do {
            try await auth.requestSyncScopes()
            guard let accessToken = await auth.currentAccessToken() else {
                throw AuthError.notConfigured
            }
            try await connectSpreadsheet(accessToken: accessToken)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Finds or creates the backing spreadsheet and gets local and remote in
    /// step.
    ///
    /// The spreadsheet ID is saved in `UserDefaults`, which doesn't survive
    /// deleting the app. So when no ID is saved, look in Drive for an
    /// existing "AnyRank Data" spreadsheet before creating a new one, and
    /// bring back any lists it has that this device doesn't: everything on
    /// a fresh install, or the lists missing after a few were made before
    /// sync was turned on. When both sides have a list, the local copy wins,
    /// matching the rest of the sync model.
    func connectSpreadsheet(accessToken: String) async throws {
        restoredListCount = nil
        var adoptedExisting = false
        if spreadsheetID == nil {
            if let existing = try await findExistingSpreadsheet(accessToken: accessToken) {
                spreadsheetID = existing
                adoptedExisting = true
            } else {
                spreadsheetID = try await sheetsClient.createSpreadsheet(
                    title: Self.spreadsheetTitle,
                    accessToken: accessToken
                )
            }
        }
        guard let id = spreadsheetID, let repository else { return }
        status = .ready(spreadsheetID: id, lastSyncedAt: nil)

        let localLists = repository.lists
        if adoptedExisting {
            let localIDs = Set(localLists.map(\.id))
            let missing = try await fetchRemoteLists(spreadsheetID: id, accessToken: accessToken)
                .filter { !localIDs.contains($0.id) }
            if !missing.isEmpty {
                repository.replaceLists(localLists + missing)
                restoredListCount = missing.count
                status = .ready(spreadsheetID: id, lastSyncedAt: Date())
            }
        }

        // Write what this device had. Restored lists are already in the
        // Sheet; the index push after these covers the full merged set.
        for list in localLists {
            schedulePush(for: list.id)
        }
    }

    /// The app's existing backup in Drive, if any. When there are several
    /// (earlier versions created a fresh spreadsheet after every reinstall),
    /// prefer the most recently modified one that actually lists something
    /// in its `_index` tab.
    private func findExistingSpreadsheet(accessToken: String) async throws -> String? {
        let candidates = try await sheetsClient.findSpreadsheets(
            titled: Self.spreadsheetTitle,
            accessToken: accessToken
        )
        guard candidates.count > 1 else { return candidates.first?.id }
        for candidate in candidates {
            let index = (try? await sheetsClient.readTab(
                spreadsheetID: candidate.id,
                tabName: SheetsIndexCodec.tabName,
                accessToken: accessToken
            )) ?? ""
            if let entries = try? SheetsIndexCodec.decode(index), !entries.isEmpty {
                return candidate.id
            }
        }
        return candidates.first?.id
    }

    func disableSync() {
        status = .disabled
        restoredListCount = nil
        spreadsheetID = nil
        pendingPushIDs.removeAll()
        pushTask?.cancel()
        pushTask = nil
    }

    // MARK: SyncObserver

    func didChangeList(_ list: RankList) {
        guard status.isEnabled else { return }
        schedulePush(for: list.id)
    }

    func didDeleteList(_ list: RankList) {
        guard status.isEnabled else { return }
        Task {
            await deleteRemote(listID: list.id)
            // The `_index` tab now has one fewer row — rewrite it so cloud
            // and local agree on the set of lists.
            await pushIndex()
        }
    }

    // MARK: Sheets tab naming

    /// The tab name for a list's items sheet. UUID-based so rename doesn't
    /// orphan the tab or force a Sheets-side rename. `_index` maps back
    /// to the human-readable display name.
    private static func itemsTabName(for listID: UUID) -> String {
        listID.uuidString
    }

    /// The comparisons sheet sibling. Same UUID + a suffix.
    private static func comparisonsTabName(for listID: UUID) -> String {
        "\(listID.uuidString)_comparisons"
    }

    // MARK: Push (debounced)

    /// Force every pending debounced push to run immediately. Called from
    /// `AnyRankApp` when the scene moves to `.background` — the contract
    /// is "when the user stops interacting, the Sheet matches local."
    ///
    /// No-op when sync is disabled.
    func flushNow() async {
        guard status.isEnabled else { return }
        pushTask?.cancel()
        pushTask = nil
        await flushPendingPushes()
    }

    private func schedulePush(for listID: UUID) {
        pendingPushIDs.insert(listID)
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.flushPendingPushes()
        }
    }

    private func flushPendingPushes() async {
        let ids = pendingPushIDs
        pendingPushIDs.removeAll()
        for id in ids {
            guard let list = repository?.lists.first(where: { $0.id == id }) else { continue }
            await push(list: list)
        }
        // After per-list pushes, rewrite the `_index` tab so list metadata
        // (category, custom fields, threshold, etc.) stays in sync. The
        // index reflects the entire set of lists, not just the changed ones.
        await pushIndex()
        if case .ready(let id, _) = status {
            status = .ready(spreadsheetID: id, lastSyncedAt: Date())
        }
    }

    /// Write the `_index` tab from the current repository state. Called
    /// after any change to the list set (push flush, delete) so a pull on
    /// another device can reconstruct lists with the right category and
    /// custom field names.
    private func pushIndex() async {
        guard case .ready(let id, _) = status else { return }
        guard let accessToken = await auth.currentAccessToken() else { return }
        guard let repository else { return }

        let csv = SheetsIndexCodec.encode(lists: repository.lists)
        do {
            try await sheetsClient.upsertTab(
                spreadsheetID: id,
                tabName: SheetsIndexCodec.tabName,
                csv: csv,
                accessToken: accessToken
            )
        } catch {
            status = .error("Index push failed: \(error.localizedDescription)")
        }
    }

    private func push(list: RankList) async {
        guard case .ready(let id, _) = status else { return }
        guard let accessToken = await auth.currentAccessToken() else { return }

        let itemsCSV = ListCSVCodec.encodeItems(of: list)
        let comparisonsCSV = ListCSVCodec.encodeComparisons(of: list)

        do {
            try await sheetsClient.upsertTab(
                spreadsheetID: id,
                tabName: Self.itemsTabName(for: list.id),
                csv: itemsCSV,
                accessToken: accessToken
            )
            try await sheetsClient.upsertTab(
                spreadsheetID: id,
                tabName: Self.comparisonsTabName(for: list.id),
                csv: comparisonsCSV,
                accessToken: accessToken
            )
        } catch {
            status = .error("Push failed: \(error.localizedDescription)")
        }
    }

    private func deleteRemote(listID: UUID) async {
        guard case .ready(let id, _) = status else { return }
        guard let accessToken = await auth.currentAccessToken() else { return }
        try? await sheetsClient.deleteTab(
            spreadsheetID: id,
            tabName: Self.itemsTabName(for: listID),
            accessToken: accessToken
        )
        try? await sheetsClient.deleteTab(
            spreadsheetID: id,
            tabName: Self.comparisonsTabName(for: listID),
            accessToken: accessToken
        )
    }

    // MARK: Pull

    /// Pull every tab from the spreadsheet and seed the local store from
    /// it. Used as a recovery path only — see semantics below.
    ///
    /// Semantics, deliberately simple:
    ///   - Local is the primary store. We don't pull on every launch.
    ///   - Pull fires only when local is empty: a fresh install, a
    ///     reinstall after uninstalling, or the user wiping the app's
    ///     storage. In every other case the local CSVs are authoritative
    ///     and `bootstrapIfReady` becomes a no-op past the auth check.
    ///   - On success (when the empty-local case fires), every list from
    ///     the Sheet is added to the local store. Subsequent edits push
    ///     back through the normal debounced path.
    ///   - On failure (network error, auth error, malformed CSV), local
    ///     stays empty. The user can start creating lists locally and
    ///     they'll push to the Sheet alongside the orphaned remote data;
    ///     the cleanup is theirs to do in the spreadsheet directly.
    func pullChanges() async {
        guard case .ready(let id, _) = status else { return }
        guard let accessToken = await auth.currentAccessToken() else { return }
        guard let repository else { return }

        // Local is the source of truth. Once any list exists locally we
        // never pull again — the Sheet is a one-way backup destination,
        // not an authoritative read source.
        guard repository.lists.isEmpty else { return }

        do {
            let pulledLists = try await fetchRemoteLists(spreadsheetID: id, accessToken: accessToken)
            // Wholesale swap. `replaceLists` does not re-fire the sync
            // observer, so this doesn't trigger an immediate push back.
            repository.replaceLists(pulledLists)
            status = .ready(spreadsheetID: id, lastSyncedAt: Date())
        } catch {
            status = .error("Pull failed: \(error.localizedDescription)")
        }
    }

    /// Read every list out of the spreadsheet without touching the local
    /// store.
    ///
    /// Reads the `_index` tab first to recover list metadata (category,
    /// custom field names, re-rank threshold). If `_index` is missing — for
    /// example, the spreadsheet was hand-created or pre-dates the index
    /// format — every remaining tab is imported as a Custom list as a best
    /// effort.
    private func fetchRemoteLists(spreadsheetID id: String, accessToken: String) async throws -> [RankList] {
        let indexText = (try? await sheetsClient.readTab(
            spreadsheetID: id,
            tabName: SheetsIndexCodec.tabName,
            accessToken: accessToken
        )) ?? ""
        let entries = (try? SheetsIndexCodec.decode(indexText)) ?? []

        var pulledLists: [RankList] = []
        if !entries.isEmpty {
            // Structured pull: use _index to reconstruct each list.
            for entry in entries {
                let list = entry.makeList()
                await populate(list: list, fromSpreadsheet: id, accessToken: accessToken)
                pulledLists.append(list)
            }
        } else {
            // Fallback: no `_index` — best-effort import each non-system
            // tab as a Custom list. Tab-name shape decides the list's
            // identity: a UUID-named tab (our current format) reuses
            // that UUID so subsequent pushes hit the same tab; any
            // other tab name is treated as a legacy display-name tab
            // and gets a fresh UUID plus its name preserved.
            let tabs = try await sheetsClient.listTabs(spreadsheetID: id, accessToken: accessToken)
            for tab in tabs where !tab.hasSuffix("_comparisons") && tab != SheetsIndexCodec.tabName {
                let list: RankList
                if let parsedID = UUID(uuidString: tab) {
                    list = RankList(id: parsedID, name: tab, category: .custom)
                } else {
                    list = RankList(name: tab, category: .custom)
                }
                // Read by literal tab name here rather than via
                // `populate` — populate keys off the list's UUID,
                // which for legacy display-name tabs doesn't match.
                let itemsCSV = (try? await sheetsClient.readTab(
                    spreadsheetID: id,
                    tabName: tab,
                    accessToken: accessToken
                )) ?? ""
                // A blank tab isn't a list — it's the "Sheet1" every new
                // spreadsheet starts with. (Lists the app pushes always
                // have at least a header row.)
                guard !itemsCSV.isEmpty else { continue }
                try? ListCSVCodec.decodeItems(into: list, from: itemsCSV)
                if let comparisonsCSV = try? await sheetsClient.readTab(
                    spreadsheetID: id,
                    tabName: "\(tab)_comparisons",
                    accessToken: accessToken
                ) {
                    try? ListCSVCodec.decodeComparisons(into: list, from: comparisonsCSV)
                }
                pulledLists.append(list)
            }
        }
        return pulledLists
    }

    /// Pull a single list's items and comparisons tabs into `list`. Used by
    /// both pull paths; isolated here so the structured and fallback flows
    /// behave identically once they know the list's identity. Tabs are
    /// keyed by the list's UUID, so renames don't invalidate the mapping.
    ///
    /// Legacy-shape safety net: for sheets that pre-date the UUID-keyed
    /// tab scheme (name-keyed tabs paired with a modern `_index`), fall
    /// back to reading by `list.name` when the UUID-keyed read returns
    /// empty. No data loss migrating in either direction — the next
    /// push will re-emit the tabs under the UUID scheme.
    private func populate(list: RankList, fromSpreadsheet id: String, accessToken: String) async {
        let uuidItems = (try? await sheetsClient.readTab(
            spreadsheetID: id,
            tabName: Self.itemsTabName(for: list.id),
            accessToken: accessToken
        )) ?? ""
        let itemsCSV: String
        if uuidItems.isEmpty {
            itemsCSV = (try? await sheetsClient.readTab(
                spreadsheetID: id,
                tabName: list.name,
                accessToken: accessToken
            )) ?? ""
        } else {
            itemsCSV = uuidItems
        }
        try? ListCSVCodec.decodeItems(into: list, from: itemsCSV)

        let uuidComparisons = try? await sheetsClient.readTab(
            spreadsheetID: id,
            tabName: Self.comparisonsTabName(for: list.id),
            accessToken: accessToken
        )
        let comparisonsCSV: String?
        if let uuidComparisons {
            comparisonsCSV = uuidComparisons
        } else {
            comparisonsCSV = try? await sheetsClient.readTab(
                spreadsheetID: id,
                tabName: "\(list.name)_comparisons",
                accessToken: accessToken
            )
        }
        if let comparisonsCSV {
            try? ListCSVCodec.decodeComparisons(into: list, from: comparisonsCSV)
        }
    }

    // MARK: Persistence of spreadsheet ID

    private func persistSpreadsheetID() {
        guard let email = auth.signedInUser?.email else { return }
        let key = "syncSpreadsheetID.\(email)"
        if let id = spreadsheetID {
            UserDefaults.standard.set(id, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func restoreSpreadsheetID() -> String? {
        guard let email = auth.signedInUser?.email else { return nil }
        return UserDefaults.standard.string(forKey: "syncSpreadsheetID.\(email)")
    }

    // MARK: Preview helper

    /// Builds a non-functional coordinator for previews. Wires no real
    /// dependencies so views can render their sync status UI without
    /// triggering any network or auth code.
    @MainActor
    static func preview(status: Status = .disabled) -> SyncCoordinator {
        let stub = SyncCoordinator(
            repository: Repository(storage: MemoryListStorage()),
            auth: AuthSession.previewSignedOut(),
            sheetsClient: GoogleSheetsClient()
        )
        stub.status = status
        return stub
    }
}
