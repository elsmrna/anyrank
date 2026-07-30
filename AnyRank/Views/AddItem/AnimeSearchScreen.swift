import SwiftUI

/// Anime search. Mirrors `BookSearchScreen` in shape — type-to-search,
/// loading state, results list — with a secondary line showing format +
/// season/year to disambiguate multi-season or remake results.
struct AnimeSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.animeService) private var service

    @State private var query: String = ""
    @State private var results: [AnimeSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("Search anime", text: $query)
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
                                Text(result.title)
                                Text(secondaryText(for: result))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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

    /// Compact "format · year · N eps" line. Skips segments that are
    /// unknown so the label stays readable.
    private func secondaryText(for result: AnimeSearchResult) -> String {
        var parts: [String] = []
        if let format = result.format?.displayFormat { parts.append(format) }
        if let year = result.seasonYear { parts.append(String(year)) }
        if let eps = result.episodeCount, eps > 1 { parts.append("\(eps) eps") }
        return parts.joined(separator: " · ")
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

    private func select(_ result: AnimeSearchResult) {
        var staged = StagedItem(name: result.title, category: .anime)
        staged.anime = result
        onIdentified(staged)
    }
}

private extension String {
    /// AniList emits formats in ALL_CAPS ("TV", "MOVIE", "OVA", "ONA",
    /// "SPECIAL", "MUSIC"). Present them a bit more gently to users.
    var displayFormat: String? {
        switch self {
        case "TV": return "TV"
        case "MOVIE": return "Movie"
        case "OVA": return "OVA"
        case "ONA": return "ONA"
        case "SPECIAL": return "Special"
        case "MUSIC": return "Music"
        default: return isEmpty ? nil : self.capitalized
        }
    }
}

#Preview {
    NavigationStack {
        AnimeSearchScreen(onIdentified: { _ in })
    }
}
