import SwiftUI

/// Movies search. Uses the `MovieSearchService` from environment.
struct MovieSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.movieService) private var service

    var body: some View {
        CatalogSearchScreen(
            prompt: "Search movies",
            category: .movies,
            emptyHint: "Search by title",
            search: { try await service.search(query: $0) },
            row: { SearchRowContent(title: $0.title, subtitle: $0.releaseYear.map(String.init), imageURL: $0.posterURL) },
            onSelect: select
        )
    }

    private func select(_ result: MovieSearchResult) {
        var staged = StagedItem(name: result.title, category: .movies)
        staged.movie = result
        onIdentified(staged)
    }
}

#Preview {
    NavigationStack {
        MovieSearchScreen(onIdentified: { _ in })
    }
}
