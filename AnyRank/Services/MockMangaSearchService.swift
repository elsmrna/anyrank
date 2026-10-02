import Foundation

/// Canned manga results for previews and tests.
struct MockMangaSearchService: MangaSearchService {

    func searchManga(query: String) async throws -> [MangaSearchResult] {
        guard !query.isEmpty else { return Self.pool }
        let lower = query.lowercased()
        let filtered = Self.pool.filter {
            $0.title.lowercased().contains(lower)
                || $0.alternateTitles.contains(where: { $0.lowercased().contains(lower) })
        }
        return filtered.isEmpty ? Self.pool : filtered
    }

    static let pool: [MangaSearchResult] = [
        manga(30002, "Berserk", "ベルセルク", 1989, nil, nil, "bx30002-Cul4OeN7bYtn.jpg"),
        manga(30001, "Monster", "MONSTER", 1994, 162, 18, "bx30001-Knby7l1jevE7.jpg"),
        manga(30656, "Vagabond", "バガボンド", 1998, nil, nil, "bx30656-9mW113O7rDnA.png"),
        manga(34632, "Goodnight Punpun", "Oyasumi Punpun", 2007, 147, 13, "bx34632-5xMDkx3pXsEh.png"),
        manga(30013, "One Piece", "ONE PIECE", 1997, nil, nil, "bx30013-BeslEMqiPhlk.jpg"),
        manga(105398, "Solo Leveling", "나 혼자만 레벨업", 2018, 201, 15, "bx105398-b673Vt5ZSuz3.jpg", format: "Manhwa"),
    ]

    private static func manga(
        _ id: Int, _ title: String, _ alternate: String, _ year: Int,
        _ chapters: Int?, _ volumes: Int?, _ cover: String, format: String = "Manga"
    ) -> MangaSearchResult {
        MangaSearchResult(
            id: id, title: title, alternateTitles: [alternate], format: format, startYear: year,
            chapterCount: chapters, volumeCount: volumes,
            coverURL: URL(string: "https://s4.anilist.co/file/anilistcdn/media/manga/cover/medium/\(cover)"),
            aniListURL: URL(string: "https://anilist.co/manga/\(id)")
        )
    }
}
