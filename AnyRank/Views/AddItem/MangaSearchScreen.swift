import SwiftUI

/// Manga search (AniList). The secondary line shows format, start year,
/// and length, which tells a manga apart from its manhwa or light-novel
/// namesakes.
struct MangaSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.mangaService) private var service

    var body: some View {
        CatalogSearchScreen(
            prompt: "Search manga",
            category: .manga,
            emptyHint: "Search by title",
            search: { try await service.searchManga(query: $0) },
            row: { SearchRowContent(title: $0.title, subtitle: secondaryText(for: $0), imageURL: $0.coverURL) },
            onSelect: select
        )
    }

    private func secondaryText(for result: MangaSearchResult) -> String {
        [result.format, result.startYear.map(String.init), MangaLength.text(chapters: result.chapterCount, volumes: result.volumeCount)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func select(_ result: MangaSearchResult) {
        var staged = StagedItem(name: result.title, category: .manga)
        staged.manga = result
        onIdentified(staged)
    }
}

#Preview {
    NavigationStack {
        MangaSearchScreen(onIdentified: { _ in })
    }
}
