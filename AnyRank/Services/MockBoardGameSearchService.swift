import Foundation

/// Canned board games for previews, tests, and until a BoardGameGeek token
/// is configured.
struct MockBoardGameSearchService: BoardGameSearchService {

    func searchBoardGames(query: String) async throws -> [BoardGameSearchResult] {
        guard !query.isEmpty else { return Self.pool }
        let lower = query.lowercased()
        let filtered = Self.pool.filter { $0.name.lowercased().contains(lower) }
        return filtered.isEmpty ? Self.pool : filtered
    }

    static let pool: [BoardGameSearchResult] = [
        .init(id: 174430, name: "Gloomhaven", yearPublished: 2017, minPlayers: 1, maxPlayers: 4, playingMinutes: 120, coverURL: nil),
        .init(id: 266192, name: "Wingspan", yearPublished: 2019, minPlayers: 1, maxPlayers: 5, playingMinutes: 70, coverURL: nil),
        .init(id: 13, name: "Catan", yearPublished: 1995, minPlayers: 3, maxPlayers: 4, playingMinutes: 120, coverURL: nil),
        .init(id: 167791, name: "Terraforming Mars", yearPublished: 2016, minPlayers: 1, maxPlayers: 5, playingMinutes: 120, coverURL: nil),
        .init(id: 178900, name: "Codenames", yearPublished: 2015, minPlayers: 2, maxPlayers: 8, playingMinutes: 15, coverURL: nil),
        .init(id: 9209, name: "Ticket to Ride", yearPublished: 2004, minPlayers: 2, maxPlayers: 5, playingMinutes: 60, coverURL: nil),
    ]
}
