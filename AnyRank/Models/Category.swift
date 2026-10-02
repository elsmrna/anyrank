import Foundation

/// A list's category. Determines metadata schema and which (if any) external
/// search service the add-item flow uses to identify items.
enum Category: String, Codable, CaseIterable, Identifiable {
    case restaurants
    case bars
    case stays
    case movies
    case books
    case anime
    case manga
    case games
    case albums
    case songs
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .restaurants: return "Restaurants"
        case .bars: return "Bars"
        case .stays: return "Stays"
        case .movies: return "Movies"
        case .books: return "Books"
        case .anime: return "Anime"
        case .manga: return "Manga"
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
        case .restaurants, .bars, .stays, .movies, .books, .anime, .manga, .games, .albums, .songs: return true
        case .custom: return false
        }
    }

    var systemIconName: String {
        switch self {
        case .restaurants: return "fork.knife"
        case .bars: return "wineglass"
        case .stays: return "bed.double"
        case .movies: return "film"
        case .books: return "book.closed"
        case .anime: return "tv"
        case .manga: return "book.pages"
        case .games: return "gamecontroller"
        case .albums: return "opticaldisc"
        case .songs: return "music.note"
        case .custom: return "list.bullet.rectangle"
        }
    }
}
