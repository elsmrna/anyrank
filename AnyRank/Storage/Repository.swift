import Foundation
import Observation

/// The single source of truth for all `RankList` data at runtime. Holds
/// the loaded lists in memory and pushes changes to the storage layer
/// and (when enabled) to the sync coordinator.
///
/// Views observe `Repository.lists` directly. Mutations go through the
/// repository's methods so persistence and sync stay coordinated.
@MainActor
@Observable
final class Repository {

    /// All lists, in their natural sorted order (most recently created first).
    private(set) var lists: [RankList] = []

    /// True after `loadAll()` has completed successfully at least once.
    /// Views can branch on this to suppress an empty-state flicker.
    private(set) var hasLoaded: Bool = false

    private let storage: ListStorage

    /// Optional sync hook. Set by `SyncCoordinator` when sync is wired up.
    /// Repository itself is sync-agnostic — it just calls the closure on
    /// mutations and lets sync decide what to do.
    var syncObserver: SyncObserver?

    init(storage: ListStorage) {
        self.storage = storage
    }

    // MARK: Lifecycle

    func loadAll() async {
        do {
            lists = try await storage.loadAll().sorted { $0.createdAt > $1.createdAt }
        } catch {
            // Errors at load are unrecoverable for v1 — fall back to empty.
            // The user can still create lists; the underlying error gets
            // surfaced if they attempt to add to a corrupted store.
            lists = []
        }
        hasLoaded = true
    }

    // MARK: List mutations

    func addList(_ list: RankList) {
        lists.insert(list, at: 0)
        persist(list)
    }

    /// Mark a list as changed so its CSV gets rewritten and sync is notified.
    /// Use after any in-place edit (name change, settings, items). Counts
    /// as using the list for the home screen's "Recent" sort.
    func touch(_ list: RankList) {
        list.lastUsedAt = Date()
        persist(list)
    }

    /// Record that the list was opened. Saved locally only: opening isn't
    /// worth a Sheets push, and the date rides along with the next change.
    func markUsed(_ list: RankList) {
        list.lastUsedAt = Date()
        Task { [storage] in
            try? await storage.save(list)
        }
    }

    func deleteList(_ list: RankList) {
        lists.removeAll { $0.id == list.id }
        Task { [storage, syncObserver] in
            try? await storage.delete(list)
            syncObserver?.didDeleteList(list)
        }
    }

    /// Wholesale swap: replace every in-memory list and the on-disk
    /// mirror with `newLists`. Used by the sync layer's pull path —
    /// the Sheet is the source of truth on read, and any list that no
    /// longer appears in the pull is dropped locally.
    ///
    /// Intentionally does NOT notify the sync observer. The whole point
    /// is to adopt remote state; firing change events would queue an
    /// immediate push of what we just pulled. This breaks the symmetry
    /// of every other mutation in this class, and is the only safe
    /// shape for the pull-then-push model.
    ///
    /// Restoring a local export passes `notifySync: true`: there the
    /// incoming lists are the new truth, and the Sheet should follow.
    func replaceLists(_ newLists: [RankList], notifySync: Bool = false) {
        let newIDs = Set(newLists.map(\.id))
        // Capture lists that exist locally but not in the incoming set,
        // BEFORE we reassign — we need the RankList references to call
        // storage.delete with.
        let removed = lists.filter { !newIDs.contains($0.id) }

        lists = newLists.sorted { $0.createdAt > $1.createdAt }

        let observer = notifySync ? syncObserver : nil
        Task { [storage] in
            for old in removed {
                try? await storage.delete(old)
                observer?.didDeleteList(old)
            }
            for newList in newLists {
                try? await storage.save(newList)
                observer?.didChangeList(newList)
            }
        }
    }

    // MARK: Item mutations

    func appendItem(_ item: RankItem, to list: RankList) {
        item.list = list
        list.items.append(item)
        touch(list)
    }

    func removeItem(_ item: RankItem, from list: RankList) {
        list.items.removeAll { $0.id == item.id }
        touch(list)
    }

    func appendComparison(_ record: ComparisonRecord, to list: RankList) {
        list.comparisons.append(record)
        // Comparisons piggy-back on the list's persistence; no separate touch.
    }

    // MARK: Private helpers

    private func persist(_ list: RankList) {
        Task { [storage, syncObserver] in
            try? await storage.save(list)
            syncObserver?.didChangeList(list)
        }
    }
}

/// Observer protocol the sync coordinator implements. Repository calls
/// these methods after persistence completes; the coordinator decides
/// whether/when to push to the cloud.
@MainActor
protocol SyncObserver: AnyObject {
    func didChangeList(_ list: RankList)
    func didDeleteList(_ list: RankList)
}
