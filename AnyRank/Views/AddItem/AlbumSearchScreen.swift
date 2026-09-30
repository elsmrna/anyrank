import SwiftUI

/// Album search. Reads from the shared `MusicSearchService`; secondary
/// text is `artist · year`.
struct AlbumSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.musicService) private var service

    var body: some View {
        CatalogSearchScreen(
            prompt: "Search albums",
            category: .albums,
            emptyHint: "Search by album or artist",
            search: { try await service.searchAlbums(query: $0) },
            row: { SearchRowContent(title: $0.title, subtitle: secondaryText(for: $0), imageURL: $0.coverURL) },
            onSelect: select
        )
    }

    private func secondaryText(for result: AlbumSearchResult) -> String {
        if let year = result.releaseYear { return "\(result.artist) · \(year)" }
        return result.artist
    }

    private func select(_ result: AlbumSearchResult) {
        var staged = StagedItem(name: result.title, category: .albums)
        staged.album = result
        onIdentified(staged)
    }
}

#Preview {
    NavigationStack {
        AlbumSearchScreen(onIdentified: { _ in })
    }
}
