import SwiftUI

/// Board game search (BoardGameGeek). The secondary line shows the year and
/// player count, which separates editions and reprints.
struct BoardGameSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.boardGameService) private var service

    var body: some View {
        CatalogSearchScreen(
            prompt: "Search board games",
            category: .boardGames,
            emptyHint: "Search by title",
            search: { try await service.searchBoardGames(query: $0) },
            row: {
                SearchRowContent(
                    title: $0.name,
                    subtitle: BoardGameText.secondary(year: $0.yearPublished, minPlayers: $0.minPlayers, maxPlayers: $0.maxPlayers),
                    imageURL: $0.coverURL
                )
            },
            onSelect: select
        )
    }

    private func select(_ result: BoardGameSearchResult) {
        var staged = StagedItem(name: result.name, category: .boardGames)
        staged.boardGame = result
        onIdentified(staged)
    }
}

#Preview {
    NavigationStack {
        BoardGameSearchScreen(onIdentified: { _ in })
    }
}
