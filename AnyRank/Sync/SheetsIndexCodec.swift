import Foundation

/// Encode and decode the `_index` tab of the synced spreadsheet. The
/// `_index` tab carries per-list metadata that CSV columns alone can't
/// represent — most importantly the list's category and its custom field
/// names. Without this tab, a pulled list can't be reconstructed faithfully.
///
/// One row per list. Columns mirror `IndexEntry` on disk so the local and
/// remote shapes stay symmetric.
///
/// `custom_field_names` is JSON-encoded into a single cell so field names
/// can contain commas, spaces, or any character without breaking the CSV.
/// A user editing the sheet by hand sees something like `["Region","Vintage"]`
/// in that cell — not pretty but unambiguous.
enum SheetsIndexCodec {

    static let tabName = "_index"

    static let columnHeaders: [String] = [
        "id",
        "name",
        "category",
        "created_at",
        "custom_field_names",
        "rerank_prompt_threshold",
        "additions_since_last_rerank_prompt",
        "links_to_maps_location",
        "last_used_at"
    ]

    @MainActor
    static func encode(lists: [RankList]) -> String {
        var rows: [[String]] = [columnHeaders]
        let sorted = lists.sorted { $0.createdAt < $1.createdAt }
        for list in sorted {
            rows.append([
                list.id.uuidString,
                list.name,
                list.categoryRaw,
                isoFormatter.string(from: list.createdAt),
                encodeCustomFieldNames(list.customFieldNames),
                String(list.rerankPromptThreshold),
                String(list.additionsSinceLastRerankPrompt),
                list.linksToMapsLocation ? "true" : "false",
                isoFormatter.string(from: list.lastUsedAt)
            ])
        }
        return CSV.encode(rows: rows)
    }

    /// Decode `_index` tab contents to per-list metadata entries.
    /// Returns an empty array for empty/missing input. Skips malformed
    /// rows rather than throwing — losing one list's metadata shouldn't
    /// stop the rest of the pull.
    static func decode(_ text: String) throws -> [IndexEntry] {
        guard !text.isEmpty else { return [] }
        let rows = try CSV.decode(text)
        guard let header = rows.first else { return [] }
        let columnIndex = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        var entries: [IndexEntry] = []
        for row in rows.dropFirst() {
            guard let idStr = field(row, columnIndex, "id"),
                  let id = UUID(uuidString: idStr) else { continue }
            let name = field(row, columnIndex, "name") ?? ""
            let category = field(row, columnIndex, "category") ?? Category.custom.rawValue
            let createdAt = field(row, columnIndex, "created_at").flatMap { parseDate($0) } ?? Date()
            let customFields = field(row, columnIndex, "custom_field_names").flatMap { decodeCustomFieldNames($0) } ?? []
            let threshold = field(row, columnIndex, "rerank_prompt_threshold").flatMap(Int.init) ?? 10
            let additions = field(row, columnIndex, "additions_since_last_rerank_prompt").flatMap(Int.init) ?? 0
            // Older sheets pre-date this column — treat missing or empty
            // as false rather than rejecting the row.
            let linksToMaps = field(row, columnIndex, "links_to_maps_location").map { $0.lowercased() == "true" } ?? false
            let lastUsedAt = field(row, columnIndex, "last_used_at").flatMap { parseDate($0) }

            entries.append(IndexEntry(
                id: id,
                name: name,
                category: category,
                createdAt: createdAt,
                customFieldNames: customFields,
                rerankPromptThreshold: threshold,
                additionsSinceLastRerankPrompt: additions,
                linksToMapsLocation: linksToMaps,
                lastUsedAt: lastUsedAt
            ))
        }
        return entries
    }

    // MARK: Helpers

    private static func field(_ row: [String], _ columnIndex: [String: Int], _ name: String) -> String? {
        guard let idx = columnIndex[name], idx < row.count else { return nil }
        let v = row[idx]
        return v.isEmpty ? nil : v
    }

    private static func encodeCustomFieldNames(_ names: [String]) -> String {
        guard !names.isEmpty else { return "" }
        // Use JSON so field names containing commas, spaces, or quotes
        // survive round-tripping cleanly.
        guard let data = try? JSONSerialization.data(withJSONObject: names, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    private static func decodeCustomFieldNames(_ encoded: String) -> [String]? {
        guard let data = encoded.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String]
    }

    /// `nonisolated(unsafe)` because `ISO8601DateFormatter` isn't
    /// `Sendable`-annotated but Apple documents `string(from:)` and
    /// `date(from:)` as thread-safe on shared instances. We only ever
    /// call those two methods on this static.
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseDate(_ string: String) -> Date? {
        if let d = isoFormatter.date(from: string) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}

extension IndexEntry {
    init(
        id: UUID,
        name: String,
        category: String,
        createdAt: Date,
        customFieldNames: [String],
        rerankPromptThreshold: Int,
        additionsSinceLastRerankPrompt: Int,
        linksToMapsLocation: Bool = false,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.createdAt = createdAt
        self.customFieldNames = customFieldNames
        self.rerankPromptThreshold = rerankPromptThreshold
        self.additionsSinceLastRerankPrompt = additionsSinceLastRerankPrompt
        self.linksToMapsLocation = linksToMapsLocation
        self.lastUsedAt = lastUsedAt
    }
}
