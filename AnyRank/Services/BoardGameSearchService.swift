import Foundation

/// Result returned by a board game lookup. `id` is BoardGameGeek's thing ID.
struct BoardGameSearchResult: Identifiable, Equatable, Hashable, Sendable, Codable {
    let id: Int
    let name: String
    let yearPublished: Int?
    let minPlayers: Int?
    let maxPlayers: Int?
    /// BGG's listed playing time, in minutes.
    let playingMinutes: Int?
    let coverURL: URL?

    var bggURL: URL? { URL(string: "https://boardgamegeek.com/boardgame/\(id)") }
}

protocol BoardGameSearchService: Sendable {
    func searchBoardGames(query: String) async throws -> [BoardGameSearchResult]
}

enum BoardGameText {
    /// "2–4 players", "1 player", or "2+ players"-style text from a range.
    static func players(min: Int?, max: Int?) -> String? {
        switch (min, max) {
        case let (lo?, hi?) where lo == hi: return "\(lo) player\(lo == 1 ? "" : "s")"
        case let (lo?, hi?) where hi > lo: return "\(lo)–\(hi) players"
        case let (lo?, _): return "\(lo)+ players"
        case let (nil, hi?): return "Up to \(hi) players"
        default: return nil
        }
    }

    /// "2017 · 1–4 players", skipping whatever's unknown.
    static func secondary(year: Int?, minPlayers: Int?, maxPlayers: Int?) -> String? {
        let parts = [year.map(String.init), players(min: minPlayers, max: maxPlayers)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
