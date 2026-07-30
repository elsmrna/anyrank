import SwiftUI

/// Game search. Mirrors `BookSearchScreen`/`AnimeSearchScreen` in shape.
/// Secondary text shows platforms (truncated to 3, with "+N more" hint)
/// and release year — usually enough to disambiguate remasters, DLC
/// versions, and multi-platform titles.
struct GameSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.gameService) private var service

    @State private var query: String = ""
    @State private var results: [GameSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("Search games", text: $query)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .focused($searchFieldFocused)
                    .onChange(of: query) { _, newValue in
                        Task { await runSearch(newValue) }
                    }
                    .onAppear {
                        searchFieldFocused = true
                        Task { await runSearch("") }
                    }
            }

            if isSearching {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            } else {
                Section {
                    ForEach(results) { result in
                        Button {
                            select(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                let secondary = secondaryText(for: result)
                                if !secondary.isEmpty {
                                    Text(secondary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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

    private func runSearch(_ query: String) async {
        isSearching = true
        errorMessage = nil
        do {
            results = try await service.search(query: query)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        isSearching = false
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
