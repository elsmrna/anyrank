import Foundation

/// Where an import's items came from. Each source knows its category (if
/// it's tied to one), how the user provides input, and how it names a list.
enum ImportSourceKind: String, Codable, CaseIterable, Identifiable {
    case steam
    case letterboxd
    case goodreads
    case storyGraph
    case pastedList

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steam:      return "Steam"
        case .letterboxd: return "Letterboxd"
        case .goodreads:  return "Goodreads"
        case .storyGraph: return "StoryGraph"
        case .pastedList: return "Pasted list"
        }
    }

    /// One line under the name on the source picker.
    var tagline: String {
        switch self {
        case .steam:      return "Your whole game library"
        case .letterboxd: return "Films you've logged"
        case .goodreads:  return "Your Read shelf"
        case .storyGraph: return "Books you've read"
        case .pastedList: return "One item per line, any category"
        }
    }

    var systemImage: String {
        switch self {
        case .steam:      return "gamecontroller"
        case .letterboxd: return "film"
        case .goodreads:  return "books.vertical"
        case .storyGraph: return "book"
        case .pastedList: return "list.bullet.clipboard"
        }
    }

    /// The category this source produces. Nil for a pasted list, which
    /// takes the target list's category.
    var category: Category? {
        switch self {
        case .steam:                  return .games
        case .letterboxd:             return .movies
        case .goodreads, .storyGraph: return .books
        case .pastedList:             return nil
        }
    }

    var defaultListName: String {
        switch self {
        case .steam:      return "Steam library"
        case .letterboxd: return "Letterboxd films"
        case .goodreads:  return "Goodreads books"
        case .storyGraph: return "StoryGraph books"
        case .pastedList: return "Imported list"
        }
    }

    /// Whether this source can feed a list of `category`.
    func canTarget(_ category: Category) -> Bool {
        self.category == nil || self.category == category
    }
}

/// An in-progress, one-time import into a list: the queue of items still
/// waiting to be ranked, plus running counts. Persisted locally so the user
/// can put the app down mid-spree and pick it back up later. Not synced —
/// only ranked items become part of the list.
struct ImportSession: Codable, Identifiable, Equatable {
    let id: UUID
    let listID: UUID
    let source: ImportSourceKind
    let startedAt: Date
    /// Items still to rank, in the order they'll be offered.
    var pending: [StagedItem]
    var rankedCount: Int = 0
    /// Items the user said "not this one" to — dropped, never added.
    var removedCount: Int = 0

    var total: Int { pending.count + rankedCount + removedCount }
    var handledCount: Int { rankedCount + removedCount }

    var progress: Double {
        total == 0 ? 1 : Double(handledCount) / Double(total)
    }
}
