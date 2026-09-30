import SwiftUI

/// Anime search. Secondary line shows format + year + episode count to
/// disambiguate multi-season or remake results.
struct AnimeSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.animeService) private var service

    var body: some View {
        CatalogSearchScreen(
            prompt: "Search anime",
            category: .anime,
            emptyHint: "Search by title",
            search: { try await service.search(query: $0) },
            row: { SearchRowContent(title: $0.title, subtitle: secondaryText(for: $0), imageURL: $0.coverURL) },
            onSelect: select
        )
    }

    /// Compact "format · year · N eps" line. Skips segments that are
    /// unknown so the label stays readable.
    private func secondaryText(for result: AnimeSearchResult) -> String {
        var parts: [String] = []
        if let format = result.format?.displayFormat { parts.append(format) }
        if let year = result.seasonYear { parts.append(String(year)) }
        if let eps = result.episodeCount, eps > 1 { parts.append("\(eps) eps") }
        return parts.joined(separator: " · ")
    }

    private func select(_ result: AnimeSearchResult) {
        var staged = StagedItem(name: result.title, category: .anime)
        staged.anime = result
        onIdentified(staged)
    }
}

private extension String {
    /// AniList emits formats in ALL_CAPS ("TV", "MOVIE", "OVA", "ONA",
    /// "SPECIAL", "MUSIC"). Present them a bit more gently to users.
    var displayFormat: String? {
        switch self {
        case "TV": return "TV"
        case "MOVIE": return "Movie"
        case "OVA": return "OVA"
        case "ONA": return "ONA"
        case "SPECIAL": return "Special"
        case "MUSIC": return "Music"
        default: return isEmpty ? nil : self.capitalized
        }
    }
}

#Preview {
    NavigationStack {
        AnimeSearchScreen(onIdentified: { _ in })
    }
}
