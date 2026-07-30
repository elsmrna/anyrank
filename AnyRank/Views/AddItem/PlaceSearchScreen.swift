import SwiftUI

/// Places picker used by Restaurants, Bars, and Custom lists that opted
/// into `linksToMapsLocation`. The `category` it stages into is passed
/// in explicitly so a Custom list staging via this screen produces a
/// `.custom` item rather than a `.restaurants` one.
///
/// Sign-in gating: Google Places is positioned as a sign-in perk. When
/// the user isn't signed in, the screen replaces the search field with
/// a prompt that triggers `AuthSession.signIn()`. Under the hood the
/// SDK uses an API key, not OAuth — the gate is a UX choice, not a
/// technical requirement.
struct PlaceSearchScreen: View {
    /// Type bias for the autocomplete predictions. Restaurants/Bars
    /// constrain to those types; Custom lists pass `.any` for an
    /// unbiased search.
    let kind: PlacesSearchKind

    /// Category to stamp on the produced `StagedItem`. Lets a Custom
    /// list use this same screen without misclassifying items.
    let stagedCategory: Category

    let onIdentified: (StagedItem) -> Void

    @Environment(\.placesService) private var service
    @Environment(AuthSession.self) private var auth

    @State private var query: String = ""
    @State private var results: [PlaceSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    /// Focus the search field on appear so the keyboard is up
    /// immediately — one less tap to start typing.
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        if auth.signedInUser == nil {
            signInGate
        } else {
            searchList
        }
    }

    // MARK: Sign-in gate

    private var signInGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sign in to look up places")
                .font(.title3.weight(.semibold))
            Text("Google Places search is available once you sign in with your Google account. Items will be tied to their canonical Maps entry.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await auth.signIn() }
            } label: {
                if auth.isSigningIn {
                    ProgressView()
                } else {
                    Label("Sign in with Google", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(auth.isSigningIn)
            if let err = auth.lastError {
                Text(err.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Search list

    private var searchList: some View {
        List {
            Section {
                TextField("Search places", text: $query)
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
                                Text(result.address)
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

    private func runSearch(_ query: String) async {
        isSearching = true
        errorMessage = nil
        do {
            results = try await service.search(query: query, kind: kind)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        isSearching = false
    }

    private func select(_ result: PlaceSearchResult) {
        var staged = StagedItem(name: result.name, category: stagedCategory)
        staged.place = result
        onIdentified(staged)
    }
}

#Preview("Signed in — Restaurants") {
    NavigationStack {
        PlaceSearchScreen(
            kind: .restaurant,
            stagedCategory: .restaurants,
            onIdentified: { _ in }
        )
    }
    .environment(AuthSession.previewSignedIn())
}

#Preview("Signed in — Custom (any)") {
    NavigationStack {
        PlaceSearchScreen(
            kind: .any,
            stagedCategory: .custom,
            onIdentified: { _ in }
        )
    }
    .environment(AuthSession.previewSignedIn())
}

#Preview("Signed out — gate") {
    NavigationStack {
        PlaceSearchScreen(
            kind: .restaurant,
            stagedCategory: .restaurants,
            onIdentified: { _ in }
        )
    }
    .environment(AuthSession.previewSignedOut())
}
