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

    var body: some View {
        if auth.signedInUser == nil {
            signInGate
        } else {
            CatalogSearchScreen(
                prompt: "Search places",
                category: stagedCategory,
                emptyHint: "Search by name or neighborhood",
                search: { try await service.search(query: $0, kind: kind) },
                row: { SearchRowContent(title: $0.name, subtitle: $0.address) },
                onSelect: select
            )
        }
    }

    // MARK: Sign-in gate

    private var signInGate: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(spacing: 8) {
                Text("Sign in to look up places")
                    .font(.display(.title2))
                    .foregroundStyle(Theme.textPrimary)
                Text("Place search uses Google Maps, so each spot is tied to its real address and map link.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let err = auth.lastError {
                Text(err.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                Task { await auth.signIn() }
            } label: {
                if auth.isSigningIn {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Text("Sign in with Google")
                }
            }
            .buttonStyle(.primary)
            .disabled(auth.isSigningIn)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 8)
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
