import SwiftUI

/// Books search. Shows author + year as the secondary detail since title
/// alone often isn't enough to disambiguate.
struct BookSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.bookService) private var service

    var body: some View {
        CatalogSearchScreen(
            prompt: "Search books",
            category: .books,
            emptyHint: "Search by title or author",
            search: { try await service.search(query: $0) },
            row: { SearchRowContent(title: $0.title, subtitle: secondaryText(for: $0), imageURL: $0.coverURL) },
            onSelect: select
        )
    }

    private func secondaryText(for result: BookSearchResult) -> String {
        if let year = result.publicationYear {
            return "\(result.author) · \(year)"
        }
        return result.author
    }

    private func select(_ result: BookSearchResult) {
        var staged = StagedItem(name: result.title, category: .books)
        staged.book = result
        onIdentified(staged)
    }
}

#Preview {
    NavigationStack {
        BookSearchScreen(onIdentified: { _ in })
    }
}
