import Foundation

/// Canned-results implementation used by previews, snapshot tests, and
/// as a fallback when the live AniList service is unavailable.
struct MockAnimeSearchService: AnimeSearchService {

    var simulatedDelay: Duration = .zero

    func search(query: String) async throws -> [AnimeSearchResult] {
        if simulatedDelay > .zero {
            try? await Task.sleep(for: simulatedDelay)
        }
        guard !query.isEmpty else { return Self.pool }
        let lower = query.lowercased()
        let filtered = Self.pool.filter {
            $0.title.lowercased().contains(lower)
                || $0.alternateTitles.contains(where: { $0.lowercased().contains(lower) })
        }
        return filtered.isEmpty ? Self.pool : filtered
    }

    private static let pool: [AnimeSearchResult] = [
        .init(
            id: 21,
            title: "One Piece",
            alternateTitles: ["ワンピース"],
            format: "TV",
            seasonYear: 1999,
            episodeCount: nil, // ongoing
            coverURL: nil,
            aniListURL: URL(string: "https://anilist.co/anime/21")
        ),
        .init(
            id: 16498,
            title: "Attack on Titan",
            alternateTitles: ["Shingeki no Kyojin", "進撃の巨人"],
            format: "TV",
            seasonYear: 2013,
            episodeCount: 25,
            coverURL: nil,
            aniListURL: URL(string: "https://anilist.co/anime/16498")
        ),
        .init(
            id: 1,
            title: "Cowboy Bebop",
            alternateTitles: ["カウボーイビバップ"],
            format: "TV",
            seasonYear: 1998,
            episodeCount: 26,
            coverURL: nil,
            aniListURL: URL(string: "https://anilist.co/anime/1")
        ),
        .init(
            id: 199,
            title: "Spirited Away",
            alternateTitles: ["Sen to Chihiro no Kamikakushi", "千と千尋の神隠し"],
            format: "MOVIE",
            seasonYear: 2001,
            episodeCount: 1,
            coverURL: nil,
            aniListURL: URL(string: "https://anilist.co/anime/199")
        ),
        .init(
            id: 30,
            title: "Neon Genesis Evangelion",
            alternateTitles: ["Shin Seiki Evangelion", "新世紀エヴァンゲリオン"],
            format: "TV",
            seasonYear: 1995,
            episodeCount: 26,
            coverURL: nil,
            aniListURL: URL(string: "https://anilist.co/anime/30")
        ),
        .init(
            id: 5114,
            title: "Fullmetal Alchemist: Brotherhood",
            alternateTitles: ["Hagane no Renkinjutsushi", "鋼の錬金術師 FULLMETAL ALCHEMIST"],
            format: "TV",
            seasonYear: 2009,
            episodeCount: 64,
            coverURL: nil,
            aniListURL: URL(string: "https://anilist.co/anime/5114")
        )
    ]
}
