import SwiftUI

/// Song search. Secondary text is `artist · album` — the album title
/// disambiguates same-title covers and live vs studio versions.
struct SongSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.musicService) private var service

    @State private var query: String = ""
    @State private var results: [SongSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("Search songs", text: $query)
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
                                    .lineLimit(1)
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

    private func secondaryText(for result: SongSearchResult) -> String {
        if let album = result.albumTitle, !album.isEmpty {
            return "\(result.artist) · \(album)"
        }
        return result.artist
    }

    private func runSearch(_ query: String) async {
        isSearching = true
        errorMessage = nil
        do {
            results = try await service.searchSongs(query: query)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        isSearching = false
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
