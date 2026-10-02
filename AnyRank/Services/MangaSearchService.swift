import Foundation

/// Result returned by a manga lookup. Same title handling as
/// `AnimeSearchResult` (English preferred, romaji fallback).
///
/// `format` uses AniList's raw strings ("MANGA", "NOVEL", "ONE_SHOT"), so a
/// new format doesn't need a migration. Manhwa and manhua come back as
/// "MANGA" with a country of origin, which `displayFormat` turns into a
/// friendlier label.
struct MangaSearchResult: Identifiable, Equatable, Hashable, Sendable, Codable {
    /// AniList `media.id`.
    let id: Int
    let title: String
    let alternateTitles: [String]
    let format: String?
    let startYear: Int?
    let chapterCount: Int?
    let volumeCount: Int?
    let coverURL: URL?
    let aniListURL: URL?
}

protocol MangaSearchService: Sendable {
    func searchManga(query: String) async throws -> [MangaSearchResult]
}

enum MangaLength {
    /// "37 vols" when the volume count is known, else "327 ch", else nil
    /// (ongoing series often have neither).
    static func text(chapters: Int?, volumes: Int?, long: Bool = false) -> String? {
        if let volumes, volumes > 0 { return long ? "\(volumes) volume\(volumes == 1 ? "" : "s")" : "\(volumes) vols" }
        if let chapters, chapters > 0 { return long ? "\(chapters) chapter\(chapters == 1 ? "" : "s")" : "\(chapters) ch" }
        return nil
    }
}

enum MangaFormat {
    /// "Manga", "Light novel", "One-shot", or "Manhwa"/"Manhua" by origin.
    static func display(_ format: String?, countryOfOrigin: String? = nil) -> String? {
        switch format {
        case "MANGA":
            switch countryOfOrigin {
            case "KR": return "Manhwa"
            case "CN", "TW": return "Manhua"
            default: return "Manga"
            }
        case "NOVEL": return "Light novel"
        case "ONE_SHOT": return "One-shot"
        case let other?: return other.isEmpty ? nil : other.replacingOccurrences(of: "_", with: " ").capitalized
        case nil: return nil
        }
    }
}
