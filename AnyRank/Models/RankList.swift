import Foundation
import Observation

/// A user-created list of items belonging to a single category. Lists are
/// independent — a user can have multiple lists in the same category
/// (e.g. "Restaurants — NYC" and "Restaurants — SF").
///
/// Each `RankList` is persisted as one CSV file plus a sibling
/// `_comparisons.csv` under the app sandbox. Per-list metadata (name,
/// category, custom field names, etc.) lives in the top-level `index.json`
/// since CSV has no native place for it. See `FileListStorage`.
@Observable
@MainActor
final class RankList: Identifiable {

    let id: UUID
    var name: String
    var categoryRaw: String
    var createdAt: Date

    /// When the list was last opened or changed. Drives the home screen's
    /// default "Recent" sort. Starts at `createdAt`.
    var lastUsedAt: Date

    /// User-defined metadata field names for Custom-category lists.
    /// Empty for predefined categories. Values are stored on each
    /// `RankItem.customFieldValues` keyed by these names.
    var customFieldNames: [String]

    /// When true on a Custom-category list, items are added via the
    /// Google Places picker (same UX as Restaurants/Bars) and carry the
    /// canonical place metadata — name, address, lat/lng, Maps URL.
    /// Ignored for predefined categories (Restaurants/Bars already use
    /// Places; Movies/Books use their own services). Defaults to false
    /// so existing custom lists stay text-only on migration.
    var linksToMapsLocation: Bool

    /// Number of items added since the periodic re-rank prompt was last
    /// shown or dismissed. When this reaches `rerankPromptThreshold`, the
    /// prompt surfaces on the next list-view appearance.
    var additionsSinceLastRerankPrompt: Int

    /// How many additions trigger a periodic re-rank prompt. Defaults to 10.
    var rerankPromptThreshold: Int

    var items: [RankItem]
    var comparisons: [ComparisonRecord]

    var category: Category {
        Category(rawValue: categoryRaw) ?? .custom
    }

    /// Items in `bucket`, sorted by score descending (highest first).
    /// Used heavily by the ranking algorithm and list rendering.
    func items(in bucket: Bucket) -> [RankItem] {
        items
            .filter { $0.bucket == bucket }
            .sorted { $0.score > $1.score }
    }

    func itemsSortedByScore() -> [RankItem] {
        items.sorted { $0.score > $1.score }
    }

    init(
        id: UUID = UUID(),
        name: String,
        category: Category,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        customFieldNames: [String] = [],
        linksToMapsLocation: Bool = false,
        rerankPromptThreshold: Int = 10,
        additionsSinceLastRerankPrompt: Int = 0,
        items: [RankItem] = [],
        comparisons: [ComparisonRecord] = []
    ) {
        self.id = id
        self.name = name
        self.categoryRaw = category.rawValue
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt ?? createdAt
        self.customFieldNames = customFieldNames
        self.linksToMapsLocation = linksToMapsLocation
        self.additionsSinceLastRerankPrompt = additionsSinceLastRerankPrompt
        self.rerankPromptThreshold = rerankPromptThreshold
        self.items = items
        self.comparisons = comparisons

        // Establish back-references so item.list works without a separate setup step.
        for item in items {
            item.list = self
        }
    }
}
