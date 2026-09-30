import SwiftUI

/// Game search. Secondary text shows platforms (truncated to 3, with a
/// "+N more" hint) and release year — usually enough to disambiguate
/// remasters, DLC versions, and multi-platform titles.
struct GameSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.gameService) private var service

    var body: some View {
        CatalogSearchScreen(
            prompt: "Search games",
            category: .games,
            emptyHint: "Search by title",
            search: { try await service.search(query: $0) },
            row: { SearchRowContent(title: $0.name, subtitle: secondaryText(for: $0), imageURL: $0.coverURL) },
            onSelect: select
        )
    }

    private func secondaryText(for result: GameSearchResult) -> String {
        var parts: [String] = []
        let platformString = Self.compactPlatforms(result.platforms)
        if !platformString.isEmpty { parts.append(platformString) }
        if let year = result.firstReleaseYear { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }

    /// First 3 platforms joined with commas, with a "+N more" suffix
    /// when there are more than 3. Keeps the row readable even for
    /// cross-platform megahits.
    static func compactPlatforms(_ platforms: [String]) -> String {
        guard !platforms.isEmpty else { return "" }
        let shown = platforms.prefix(3).joined(separator: ", ")
        let remaining = platforms.count - 3
        return remaining > 0 ? "\(shown) +\(remaining) more" : shown
    }

    private func select(_ result: GameSearchResult) {
        var staged = StagedItem(name: result.name, category: .games)
        staged.game = result
        onIdentified(staged)
    }
}

#Preview {
    NavigationStack {
        GameSearchScreen(onIdentified: { _ in })
    }
}
