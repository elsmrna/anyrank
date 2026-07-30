import SwiftUI

/// Books search. Mirrors `MovieSearchScreen` in shape — type-to-search,
/// loading state, results list — but shows author + year as the secondary
/// detail since title alone often isn't enough to disambiguate.
struct BookSearchScreen: View {
    let onIdentified: (StagedItem) -> Void

    @Environment(\.bookService) private var service

    @State private var query: String = ""
    @State private var results: [BookSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("Search books", text: $query)
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

    private func secondaryText(for result: BookSearchResult) -> String {
        if let year = result.publicationYear {
            return "\(result.author) · \(year)"
        }
        return result.author
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
