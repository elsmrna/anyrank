import SwiftUI

/// Top-level sheet for adding an item. Holds the `AddItemCoordinator` and
/// dispatches to the right child screen based on the current phase.
struct AddItemFlow: View {
    let list: RankList

    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var coordinator: AddItemCoordinator

    init(list: RankList) {
        self.list = list
        _coordinator = State(initialValue: AddItemCoordinator(list: list))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                // Hide the nav bar entirely on the success screen — the
                // checkmark stands on its own and the auto-dismiss makes
                // navigation meaningless. Everywhere else the leading
                // toolbar swaps between Cancel (first step) and a back
                // chevron (later steps), so the user can undo a wrong
                // pick without abandoning the whole flow. Full cancel
                // remains available via swipe-down on the sheet.
                .toolbar(isFinished ? .hidden : .visible, for: .navigationBar)
                .toolbar {
                    if !isFinished {
                        ToolbarItem(placement: .cancellationAction) {
                            if coordinator.canGoBack {
                                Button {
                                    coordinator.back()
                                } label: {
                                    Label("Back", systemImage: "chevron.backward")
                                }
                            } else {
                                Button("Cancel") { dismiss() }
                            }
                        }
                    }
                }
        }
    }

    private var isFinished: Bool {
        if case .finished = coordinator.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .identifying:
            ItemSearchScreen(category: list.category, list: list) { staged in
                coordinator.itemIdentified(staged)
            }

        case .bucketPick(let staged):
            BucketPickerScreen(itemName: staged.name) { bucket in
                coordinator.bucketPicked(bucket)
            }

        case .comparing(let staged, let session):
            ComparisonScreen(
                newItemName: staged.name,
                newItemImageURLString: stagedImageURLString(staged),
                newItemSecondaryText: stagedSecondaryText(staged),
                session: session,
                onAnswer: { winner in coordinator.answer(winner: winner) }
            )

        case .finished(let staged, let placement):
            AddItemResultScreen(
                stagedName: staged.name,
                placement: placement,
                onDone: {
                    apply(staged: staged, placement: placement)
                    dismiss()
                }
            )
        }
    }

    private var navigationTitle: String {
        switch coordinator.phase {
        case .identifying:    return "Add to \(list.name)"
        case .bucketPick:     return "How was it?"
        case .comparing:      return "Which did you prefer?"
        case .finished:       return "Result"
        }
    }

    /// Thumbnail URL for the not-yet-persisted staged item, mirroring
    /// `RankingApplier.comparisonImageURLString(for:in:)` for existing
    /// items so the new-item card looks visually consistent.
    private func stagedImageURLString(_ staged: StagedItem) -> String? {
        switch staged.category {
        case .movies: return staged.movie?.posterURL?.absoluteString
        case .books:  return staged.book?.coverURL?.absoluteString
        case .anime:  return staged.anime?.coverURL?.absoluteString
        case .games:  return staged.game?.coverURL?.absoluteString
        case .albums: return staged.album?.coverURL?.absoluteString
        case .songs:  return staged.song?.coverURL?.absoluteString
        case .restaurants, .bars, .custom: return nil
        }
    }

    /// Secondary text for the staged item — parallel to
    /// `RankingApplier.comparisonSecondaryText(for:in:)`.
    private func stagedSecondaryText(_ staged: StagedItem) -> String? {
        switch staged.category {
        case .movies:
            return staged.movie?.releaseYear.map { String($0) }
        case .books:
            guard let book = staged.book else { return nil }
            if !book.author.isEmpty, let year = book.publicationYear {
                return "\(book.author) · \(year)"
            }
            return book.author.isEmpty ? book.publicationYear.map { String($0) } : book.author
        case .anime:
            guard let anime = staged.anime else { return nil }
            var parts: [String] = []
            if let year = anime.seasonYear { parts.append(String(year)) }
            if let eps = anime.episodeCount, eps > 1 { parts.append("\(eps) eps") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .games:
            guard let game = staged.game else { return nil }
            var parts: [String] = []
            let platforms = GameSearchScreen.compactPlatforms(game.platforms)
            if !platforms.isEmpty { parts.append(platforms) }
            if let year = game.firstReleaseYear { parts.append(String(year)) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .albums:
            guard let album = staged.album else { return nil }
            if let year = album.releaseYear { return "\(album.artist) · \(year)" }
            return album.artist
        case .songs:
            guard let song = staged.song else { return nil }
            if let album = song.albumTitle, !album.isEmpty {
                return "\(song.artist) · \(album)"
            }
            return song.artist
        case .restaurants, .bars:
            let addr = staged.place?.address ?? ""
            return addr.isEmpty ? nil : addr
        case .custom:
            let addr = staged.place?.address ?? ""
            return addr.isEmpty ? nil : addr
        }
    }

    private func apply(staged: StagedItem, placement: RankingSession.Placement) {
        let item = RankItem(
            id: staged.id,
            name: staged.name,
            bucket: placement.bucket
        )
        staged.apply(to: item)
        RankingApplier.apply(
            placement: placement,
            item: item,
            list: list,
            repository: repository
        )
    }
}

#Preview("Empty list — Restaurants") {
    let repo = PreviewSupport.emptyRepository()
    let list = RankList(name: "Restaurants", category: .restaurants)
    repo.addList(list)
    return AddItemFlow(list: list)
        .environment(repo)
}

#Preview("Populated list — Restaurants") {
    let repo = PreviewSupport.fullRestaurantsRepository()
    let list = repo.lists.first!
    return AddItemFlow(list: list)
        .environment(repo)
}
