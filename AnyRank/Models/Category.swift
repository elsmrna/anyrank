import Foundation

/// A list's category. Determines metadata schema and which (if any) external
/// search service the add-item flow uses to identify items.
enum Category: String, Codable, CaseIterable, Identifiable {
    case restaurants
    case bars
    case movies
    case books
    case anime
    case games
    case albums
    case songs
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .restaurants: return "Restaurants"
        case .bars: return "Bars"
        case .movies: return "Movies"
        case .books: return "Books"
        case .anime: return "Anime"
        case .games: return "Games"
        case .albums: return "Albums"
        case .songs: return "Songs"
        case .custom: return "Custom"
        }
    }

    /// Whether the category supports an external search API for picking items.
    /// Custom uses a free-text name + pasted link instead.
    var supportsExternalSearch: Bool {
        switch self {
        case .restaurants, .bars, .movies, .books, .anime, .games, .albums, .songs: return true
        case .custom: return false
        }
    }

    var systemIconName: String {
        switch self {
        case .restaurants: return "fork.knife"
        case .bars: return "wineglass"
        case .movies: return "film"
        case .books: return "book.closed"
        case .anime: return "tv"
        case .games: return "gamecontroller"
        case .albums: return "opticaldisc"
        case .songs: return "music.note"
        case .custom: return "list.bullet.rectangle"
        }
    }
}
