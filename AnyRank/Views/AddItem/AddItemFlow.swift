import SwiftUI

/// Top-level sheet for adding an item. Holds the `AddItemCoordinator` and
/// hands it to `PlacementFlowView`, which pushes each step.
struct AddItemFlow: View {
    let list: RankList

    @Environment(Repository.self) private var repository

    @State private var coordinator: AddItemCoordinator

    init(list: RankList) {
        self.list = list
        _coordinator = State(initialValue: AddItemCoordinator(list: list))
    }

    var body: some View {
        PlacementFlowView(
            coordinator: coordinator,
            rootTitle: "Add to \(list.name)",
            newItemImageURLString: stagedImageURLString,
            newItemSecondaryText: stagedSecondaryText,
            onCommit: apply(staged:placement:)
        ) {
            ItemSearchScreen(category: list.category, list: list) { staged in
                coordinator.itemIdentified(staged)
            }
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
