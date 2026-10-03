import SwiftUI

/// TV search (TMDB). The secondary line shows the first-air year and the
/// season count, which tells a show apart from its remake or revival.
struct TVSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.tvService) private var service

    var body: some View {
        CatalogSearchScreen(
            prompt: "Search TV shows",
            category: .tv,
            emptyHint: "Search by title",
            search: { try await service.searchShows(query: $0) },
            row: { SearchRowContent(title: $0.title, subtitle: TVShowText.secondary(year: $0.firstAirYear, seasons: $0.seasonCount), imageURL: $0.posterURL) },
            onSelect: select
        )
    }

    private func select(_ result: TVShowSearchResult) {
        var staged = StagedItem(name: result.title, category: .tv)
        staged.tv = result
        onIdentified(staged)
    }
}

enum TVShowText {
    /// "2008 · 5 seasons", skipping whatever's unknown.
    static func secondary(year: Int?, seasons: Int?) -> String? {
        let parts = [year.map(String.init), seasons.map { "\($0) season\($0 == 1 ? "" : "s")" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        TVSearchScreen(onIdentified: { _ in })
    }
}
