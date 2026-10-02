import Foundation

/// How the home screen orders lists. Persisted (as raw values) so the app
/// reopens with the last choice.
struct ListSort: Equatable {

    enum Order: String, CaseIterable, Identifiable {
        case recent
        case type
        case name

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recent: return "Recent"
            case .type:   return "Type"
            case .name:   return "Name"
            }
        }

        var systemImage: String {
            switch self {
            case .recent: return "clock"
            case .type:   return "square.grid.2x2"
            case .name:   return "textformat"
            }
        }
    }

    var order: Order = .recent
    /// Flips the default direction: least recent first, types Z→A, or
    /// names Z→A.
    var reversed = false

    /// Short label for the direction toggle.
    var directionTitle: String {
        switch (order, reversed) {
        case (.recent, false): return "Most recent"
        case (.recent, true):  return "Least recent"
        case (_, false):       return "A–Z"
        case (_, true):        return "Z–A"
        }
    }

    /// One section per category when sorting by type; a single untitled
    /// section otherwise.
    @MainActor
    func sections(_ lists: [RankList]) -> [(category: Category?, lists: [RankList])] {
        switch order {
        case .recent:
            let sorted = lists.sorted(by: Self.mostRecentFirst)
            return [(nil, reversed ? sorted.reversed() : sorted)]

        case .name:
            let sorted = lists.sorted { a, b in
                switch a.name.localizedStandardCompare(b.name) {
                case .orderedAscending:  return true
                case .orderedDescending: return false
                case .orderedSame:       return Self.mostRecentFirst(a, b)
                }
            }
            return [(nil, reversed ? sorted.reversed() : sorted)]

        case .type:
            let categories = Category.allCases.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return (reversed ? categories.reversed() : categories).compactMap { category in
                let inCategory = lists.filter { $0.category == category }.sorted(by: Self.mostRecentFirst)
                return inCategory.isEmpty ? nil : (category, inCategory)
            }
        }
    }

    @MainActor
    private static func mostRecentFirst(_ a: RankList, _ b: RankList) -> Bool {
        a.lastUsedAt != b.lastUsedAt ? a.lastUsedAt > b.lastUsedAt : a.createdAt > b.createdAt
    }
}
