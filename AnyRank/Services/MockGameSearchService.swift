import Foundation

/// Canned-results implementation of `GameSearchService` used by previews,
/// snapshot tests, and as a fallback when the Twitch/IGDB credentials
/// aren't configured.
struct MockGameSearchService: GameSearchService {

    var simulatedDelay: Duration = .zero

    func search(query: String) async throws -> [GameSearchResult] {
        if simulatedDelay > .zero {
            try? await Task.sleep(for: simulatedDelay)
        }
        guard !query.isEmpty else { return Self.pool }
        let lower = query.lowercased()
        let filtered = Self.pool.filter { $0.name.lowercased().contains(lower) }
        return filtered.isEmpty ? Self.pool : filtered
    }

    private static let pool: [GameSearchResult] = [
        .init(
            id: 1942,
            name: "The Witcher 3: Wild Hunt",
            platforms: ["PC", "PS4", "PS5", "XONE", "SW"],
            firstReleaseYear: 2015,
            coverURL: nil,
            igdbURL: URL(string: "https://www.igdb.com/games/the-witcher-3-wild-hunt"),
            summary: "Open-world RPG following Geralt of Rivia."
        ),
        .init(
            id: 1877,
            name: "Cyberpunk 2077",
            platforms: ["PC", "PS5", "XSX"],
            firstReleaseYear: 2020,
            coverURL: nil,
            igdbURL: URL(string: "https://www.igdb.com/games/cyberpunk-2077"),
            summary: "Neon-lit dystopian RPG in Night City."
        ),
        .init(
            id: 26192,
            name: "Elden Ring",
            platforms: ["PC", "PS5", "XSX"],
            firstReleaseYear: 2022,
            coverURL: nil,
            igdbURL: URL(string: "https://www.igdb.com/games/elden-ring"),
            summary: "FromSoftware's open-world take on the Souls formula."
        ),
        .init(
            id: 119277,
            name: "Hades",
            platforms: ["PC", "SW", "PS5"],
            firstReleaseYear: 2020,
            coverURL: nil,
            igdbURL: URL(string: "https://www.igdb.com/games/hades--1"),
            summary: "Roguelike escape from the underworld."
        ),
        .init(
            id: 1877,
            name: "Baldur's Gate 3",
            platforms: ["PC", "PS5", "XSX"],
            firstReleaseYear: 2023,
            coverURL: nil,
            igdbURL: URL(string: "https://www.igdb.com/games/baldurs-gate-iii"),
            summary: "Turn-based D&D RPG from Larian."
        ),
        .init(
            id: 7346,
            name: "The Legend of Zelda: Breath of the Wild",
            platforms: ["SW", "Wii U"],
            firstReleaseYear: 2017,
            coverURL: nil,
            igdbURL: URL(string: "https://www.igdb.com/games/the-legend-of-zelda-breath-of-the-wild"),
            summary: "Open-air Zelda; genre-defining."
        )
    ]
}
