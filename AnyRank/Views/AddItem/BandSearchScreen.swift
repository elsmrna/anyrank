import SwiftUI

/// Band and artist search (Deezer). The secondary line shows the fan count,
/// which tells acts with the same name apart.
struct BandSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.artistService) private var service

    var body: some View {
        CatalogSearchScreen(
            prompt: "Search bands and artists",
            category: .bands,
            emptyHint: "Search by name",
            search: { try await service.searchArtists(query: $0) },
            row: { SearchRowContent(title: $0.name, subtitle: ArtistText.fans($0.fanCount), imageURL: $0.imageURL) },
            onSelect: select
        )
    }

    private func select(_ result: ArtistSearchResult) {
        var staged = StagedItem(name: result.name, category: .bands)
        staged.band = result
        onIdentified(staged)
    }
}

#Preview {
    NavigationStack {
        BandSearchScreen(onIdentified: { _ in })
    }
}
