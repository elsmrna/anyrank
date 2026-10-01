import Foundation
import Observation
import SwiftUI

/// Owns every in-progress import, keyed by target list. At most one session
/// per list; importing more into a list that already has one appends to its
/// queue. Persisted as one small JSON file beside the list CSVs.
///
/// Not main-actor isolated so it can serve as an environment default; all
/// mutation happens from views on the main thread.
@Observable
final class ImportStore: @unchecked Sendable {

    private(set) var sessions: [ImportSession] = []

    @ObservationIgnored private let fileURL: URL?
    /// Serial so writes land in the order they were made.
    @ObservationIgnored private let writeQueue = DispatchQueue(label: "AnyRank.ImportStore.write", qos: .utility)

    /// - Parameter fileURL: where to persist; nil keeps everything in memory
    ///   (previews, tests).
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        load()
    }

    static func defaultLocation() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AnyRank", isDirectory: true)
            .appendingPathComponent("imports.json")
    }

    // MARK: Reading

    func session(for listID: UUID) -> ImportSession? {
        sessions.first { $0.listID == listID }
    }

    // MARK: Writing

    /// Start an import into `listID`, or append to the one already running.
    /// Items already queued (by ID or by match) are not added twice.
    func enqueue(_ items: [StagedItem], into listID: UUID, from source: ImportSourceKind) {
        guard !items.isEmpty else { return }
        if let index = sessions.firstIndex(where: { $0.listID == listID }) {
            let fresh = ImportMatcher.removingMatches(items, against: sessions[index].pending)
            sessions[index].pending.append(contentsOf: fresh)
        } else {
            sessions.append(ImportSession(
                id: UUID(),
                listID: listID,
                source: source,
                startedAt: Date(),
                pending: items
            ))
        }
        save()
    }

    /// The item was placed in the list.
    func markRanked(_ itemID: UUID, in listID: UUID) {
        mutate(listID) { session in
            guard let i = session.pending.firstIndex(where: { $0.id == itemID }) else { return }
            session.pending.remove(at: i)
            session.rankedCount += 1
        }
    }

    /// "Not this one": drop the item from the import without adding it.
    func remove(_ itemID: UUID, from listID: UUID) {
        mutate(listID) { session in
            guard let i = session.pending.firstIndex(where: { $0.id == itemID }) else { return }
            session.pending.remove(at: i)
            session.removedCount += 1
        }
    }

    /// Drop an item silently — used when it turns out to already be in the
    /// list (e.g. the user added it by hand mid-import).
    func discardDuplicate(_ itemID: UUID, from listID: UUID) {
        mutate(listID) { session in
            session.pending.removeAll { $0.id == itemID }
        }
    }

    /// "Skip for now": move the item to the back of the queue.
    func deferItem(_ itemID: UUID, in listID: UUID) {
        mutate(listID) { session in
            guard session.pending.count > 1,
                  let i = session.pending.firstIndex(where: { $0.id == itemID }) else { return }
            session.pending.append(session.pending.remove(at: i))
        }
    }

    /// Replace a queued item with an enriched copy (artwork, links).
    func update(_ item: StagedItem, in listID: UUID) {
        mutate(listID) { session in
            guard let i = session.pending.firstIndex(where: { $0.id == item.id }) else { return }
            session.pending[i] = item
        }
    }

    /// Stop the import: forget every item that hasn't been ranked yet.
    /// Items already ranked stay in the list.
    func abandon(_ listID: UUID) {
        sessions.removeAll { $0.listID == listID }
        save()
    }

    /// Drop sessions whose list no longer exists.
    func prune(keeping listIDs: Set<UUID>) {
        let before = sessions.count
        sessions.removeAll { !listIDs.contains($0.listID) }
        if sessions.count != before { save() }
    }

    /// Apply a change; a session whose queue empties is complete and removed.
    private func mutate(_ listID: UUID, _ change: (inout ImportSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.listID == listID }) else { return }
        change(&sessions[index])
        if sessions[index].pending.isEmpty {
            sessions.remove(at: index)
        }
        save()
    }

    // MARK: Persistence

    /// Blocks until queued writes have landed. For tests.
    func waitForPendingWrites() {
        writeQueue.sync {}
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            sessions = try JSONDecoder().decode([ImportSession].self, from: data)
        } catch {
            // A corrupt queue shouldn't take the app down; the lists
            // themselves are untouched. Start fresh.
            sessions = []
        }
    }

    private func save() {
        guard let fileURL else { return }
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        // Encode here (cheap, and captures a consistent snapshot); write on
        // a serial queue off the main thread.
        writeQueue.async {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Environment

private struct ImportStoreKey: EnvironmentKey {
    static let defaultValue = ImportStore()
}

extension EnvironmentValues {
    var importStore: ImportStore {
        get { self[ImportStoreKey.self] }
        set { self[ImportStoreKey.self] = newValue }
    }
}
