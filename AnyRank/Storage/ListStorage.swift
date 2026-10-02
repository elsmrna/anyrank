import Foundation

/// Storage abstraction over how lists are persisted. `FileListStorage`
/// writes per-list CSV files plus a top-level `index.json`. `MemoryListStorage`
/// keeps everything in-process for previews and tests.
@MainActor
protocol ListStorage: AnyObject, Sendable {
    /// Load every list from the store. Called once at app launch.
    func loadAll() async throws -> [RankList]

    /// Persist a single list (items CSV + comparisons CSV + index entry).
    /// Idempotent — calling this with no changes is cheap.
    func save(_ list: RankList) async throws

    /// Remove a list's files from disk and drop its index entry.
    func delete(_ list: RankList) async throws

    /// True if this store's contents matter (i.e. they persist beyond
    /// process lifetime). Used to gate sync coordinator wiring.
    var isPersistent: Bool { get }
}

/// On-disk implementation. Files live under
/// `<Application Support>/AnyRank/lists/`.
///
/// Layout:
///   `index.json`                       — per-list metadata (id, name, category, customFieldNames, …)
///   `<uuid>.csv`                       — items for that list, one row per item
///   `<uuid>_comparisons.csv`           — comparison audit log for that list
///
/// The index is a small JSON document rather than embedded in the CSVs
/// because CSV has no native place for list-level metadata. The same
/// information lives on the synced spreadsheet's `_index` tab.
@MainActor
final class FileListStorage: ListStorage {

    let isPersistent = true

    private let baseDirectory: URL
    private let indexFileName = "index.json"

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        try? FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Default production location: <app-support>/AnyRank/lists/.
    static func defaultLocation() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("AnyRank", isDirectory: true)
                   .appendingPathComponent("lists", isDirectory: true)
    }

    func loadAll() async throws -> [RankList] {
        let entries = try readIndex()
        var lists: [RankList] = []
        for entry in entries {
            let list = entry.makeList()

            let itemsURL = csvURL(for: list)
            if let text = try? String(contentsOf: itemsURL, encoding: .utf8), !text.isEmpty {
                try? ListCSVCodec.decodeItems(into: list, from: text)
            }

            let comparisonsURL = comparisonsURL(for: list)
            if let text = try? String(contentsOf: comparisonsURL, encoding: .utf8), !text.isEmpty {
                try? ListCSVCodec.decodeComparisons(into: list, from: text)
            }

            // Re-establish back-refs.
            for item in list.items { item.list = list }

            lists.append(list)
        }
        return lists
    }

    func save(_ list: RankList) async throws {
        // Items CSV
        let itemsText = ListCSVCodec.encodeItems(of: list)
        try itemsText.write(to: csvURL(for: list), atomically: true, encoding: .utf8)

        // Comparisons CSV
        let comparisonsText = ListCSVCodec.encodeComparisons(of: list)
        try comparisonsText.write(to: comparisonsURL(for: list), atomically: true, encoding: .utf8)

        // Update index entry for this list (preserving other entries).
        var entries = (try? readIndex()) ?? []
        entries.removeAll { $0.id == list.id }
        entries.append(IndexEntry(from: list))
        try writeIndex(entries)
    }

    func delete(_ list: RankList) async throws {
        try? FileManager.default.removeItem(at: csvURL(for: list))
        try? FileManager.default.removeItem(at: comparisonsURL(for: list))
        var entries = (try? readIndex()) ?? []
        entries.removeAll { $0.id == list.id }
        try writeIndex(entries)
    }

    // MARK: File layout helpers

    private func csvURL(for list: RankList) -> URL {
        baseDirectory.appendingPathComponent("\(list.id.uuidString).csv")
    }

    private func comparisonsURL(for list: RankList) -> URL {
        baseDirectory.appendingPathComponent("\(list.id.uuidString)_comparisons.csv")
    }

    private var indexURL: URL {
        baseDirectory.appendingPathComponent(indexFileName)
    }

    // MARK: index.json

    private func readIndex() throws -> [IndexEntry] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([IndexEntry].self, from: data)
    }

    private func writeIndex(_ entries: [IndexEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries.sorted { $0.createdAt < $1.createdAt })
        try data.write(to: indexURL, options: .atomic)
    }
}

/// In-memory store used by previews and snapshot tests. Mirrors the
/// `FileListStorage` API but keeps everything in a Swift array.
@MainActor
final class MemoryListStorage: ListStorage {
    let isPersistent = false

    private var storedLists: [RankList]

    init(initialLists: [RankList] = []) {
        self.storedLists = initialLists
    }

    func loadAll() async throws -> [RankList] {
        storedLists
    }

    func save(_ list: RankList) async throws {
        storedLists.removeAll { $0.id == list.id }
        storedLists.append(list)
    }

    func delete(_ list: RankList) async throws {
        storedLists.removeAll { $0.id == list.id }
    }
}

// MARK: index.json shape

/// Per-list metadata persisted in `index.json`. Mirrors the fields on
/// `RankList` that aren't captured by the CSV (the CSV holds items only).
struct IndexEntry: Codable, Sendable {
    let id: UUID
    var name: String
    var category: String
    var createdAt: Date
    var customFieldNames: [String]
    var rerankPromptThreshold: Int
    var additionsSinceLastRerankPrompt: Int
    /// Whether items in this list are tied to a Google Maps location.
    /// Only meaningful for Custom-category lists; predefined categories
    /// ignore it. Optional in the decoded shape so older index.json
    /// files written before this field existed still load cleanly.
    var linksToMapsLocation: Bool?
    /// Optional for index files written before the home sort existed;
    /// those lists fall back to `createdAt`.
    var lastUsedAt: Date?

    @MainActor
    init(from list: RankList) {
        self.id = list.id
        self.name = list.name
        self.category = list.categoryRaw
        self.createdAt = list.createdAt
        self.customFieldNames = list.customFieldNames
        self.rerankPromptThreshold = list.rerankPromptThreshold
        self.additionsSinceLastRerankPrompt = list.additionsSinceLastRerankPrompt
        self.linksToMapsLocation = list.linksToMapsLocation
        self.lastUsedAt = list.lastUsedAt
    }

    @MainActor
    func makeList() -> RankList {
        RankList(
            id: id,
            name: name,
            category: Category(rawValue: category) ?? .custom,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            customFieldNames: customFieldNames,
            linksToMapsLocation: linksToMapsLocation ?? false,
            rerankPromptThreshold: rerankPromptThreshold,
            additionsSinceLastRerankPrompt: additionsSinceLastRerankPrompt
        )
    }
}
