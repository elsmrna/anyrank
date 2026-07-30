import SwiftUI

/// Album search. Reads from the shared `MusicSearchService`; secondary
/// text is `artist · year`.
struct AlbumSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.musicService) private var service

    @State private var query: String = ""
    @State private var results: [AlbumSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("Search albums", text: $query)
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

    private func secondaryText(for result: AlbumSearchResult) -> String {
        if let year = result.releaseYear { return "\(result.artist) · \(year)" }
        return result.artist
    }

    private func runSearch(_ query: String) async {
        isSearching = true
        errorMessage = nil
        do {
            results = try await service.searchAlbums(query: query)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        isSearching = false
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
