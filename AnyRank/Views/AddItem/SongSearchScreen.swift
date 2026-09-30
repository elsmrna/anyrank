import SwiftUI

/// Song search. Secondary text is `artist · album` — the album title
/// disambiguates same-title covers and live vs studio versions.
struct SongSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.musicService) private var service

    var body: some View {
        CatalogSearchScreen(
            prompt: "Search songs",
            category: .songs,
            emptyHint: "Search by song or artist",
            search: { try await service.searchSongs(query: $0) },
            row: { SearchRowContent(title: $0.title, subtitle: secondaryText(for: $0), imageURL: $0.coverURL) },
            onSelect: select
        )
    }

    private func secondaryText(for result: SongSearchResult) -> String {
        if let album = result.albumTitle, !album.isEmpty {
            return "\(result.artist) · \(album)"
        }
        return result.artist
    }

    private func select(_ result: SongSearchResult) {
        var staged = StagedItem(name: result.title, category: .songs)
        staged.song = result
        onIdentified(staged)
    }
}

#Preview {
    NavigationStack {
        SongSearchScreen(onIdentified: { _ in })
    }
}
