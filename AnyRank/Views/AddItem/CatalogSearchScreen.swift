import SwiftUI

/// What a search result row displays. Each category maps its own result
/// type into this.
struct SearchRowContent {
    let title: String
    var subtitle: String? = nil
    var imageURL: URL? = nil
}

/// Shared type-to-search screen used by every category's add flow.
///
/// - Queries are debounced and run through `.task(id:)`, so a new
///   keystroke cancels the in-flight request — stale responses can never
///   overwrite fresher ones.
/// - Previous results stay on screen while the next query loads; the
///   field shows a small spinner instead of blanking the list.
struct CatalogSearchScreen<Result: Identifiable>: View {
    let prompt: String
    let category: Category
    /// Shown under the field before the user has typed anything.
    var emptyHint: String? = nil
    let search: (String) async throws -> [Result]
    let row: (Result) -> SearchRowContent
    let onSelect: (Result) -> Void

    @State private var query = ""
    @State private var results: [Result] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasLoadedOnce = false
    @State private var selections = 0
    @FocusState private var fieldFocused: Bool

    private static var debounce: Duration { .milliseconds(250) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let errorMessage {
                    message(icon: "exclamationmark.triangle", text: errorMessage)
                } else if results.isEmpty, hasLoadedOnce, !isLoading {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        if let emptyHint {
                            message(icon: category.systemIconName, text: emptyHint)
                        }
                    } else {
                        message(icon: "magnifyingglass", text: "No matches for \u{201C}\(query)\u{201D}")
                    }
                } else {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        resultRow(result)
                        if index < results.count - 1 {
                            Divider()
                                .overlay(Theme.hairline)
                                .padding(.leading, category.hasArtwork ? 72 : 64)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
            .animation(.easeOut(duration: 0.18), value: results.map(\.id))
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchField(prompt: prompt, text: $query, isLoading: isLoading, focus: $fieldFocused)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Theme.background)
        }
        .onAppear { fieldFocused = true }
        .task(id: query) { await runSearch() }
        .sensoryFeedback(.selection, trigger: selections)
    }

    private func resultRow(_ result: Result) -> some View {
        let content = row(result)
        return Button {
            selections += 1
            fieldFocused = false
            onSelect(result)
        } label: {
            HStack(spacing: 14) {
                if category.hasArtwork {
                    ArtworkView(urlString: content.imageURL?.absoluteString, category: category, width: 44, cornerRadius: 6)
                        .frame(width: 58, alignment: .leading)
                } else {
                    Image(systemName: category == .restaurants || category == .bars || category == .custom
                          ? "mappin.and.ellipse" : category.systemIconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(category.tint)
                        .frame(width: 40, height: 40)
                        .background(category.tint.opacity(0.12), in: Circle())
                        .frame(width: 50, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle = content.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowHighlightStyle())
    }

    private func message(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 24)
    }

    private func runSearch() async {
        // First load is immediate (suggestions for an empty query); after
        // that, wait for a pause in typing.
        if hasLoadedOnce {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
        }
        isLoading = true
        do {
            let found = try await search(query)
            guard !Task.isCancelled else { return }
            results = found
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
            results = []
        }
        isLoading = false
        hasLoadedOnce = true
    }
}

/// Soft background highlight while a list-style row is pressed.
private struct RowHighlightStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surfaceMuted)
                    .padding(.horizontal, -10)
                    .opacity(configuration.isPressed ? 1 : 0)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
