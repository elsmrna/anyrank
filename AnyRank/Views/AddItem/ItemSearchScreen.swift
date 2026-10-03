import SwiftUI

/// Phase 1 of add-item: identify what's being added. Dispatches to a
/// category-specific child view. Restaurants and Bars share the Places
/// path; Movies has its own; Custom shows a free-form sheet.
struct ItemSearchScreen: View {
    let category: Category
    let list: RankList
    let onIdentified: (StagedItem) -> Void

    var body: some View {
        switch category {
        case .restaurants:
            PlaceSearchScreen(
                kind: .restaurant,
                stagedCategory: .restaurants,
                onIdentified: onIdentified
            )
        case .bars:
            PlaceSearchScreen(
                kind: .bar,
                stagedCategory: .bars,
                onIdentified: onIdentified
            )
        case .stays:
            PlaceSearchScreen(
                kind: .lodging,
                stagedCategory: .stays,
                onIdentified: onIdentified
            )
        case .movies:
            MovieSearchScreen(onIdentified: onIdentified)
        case .tv:
            TVSearchScreen(onIdentified: onIdentified)
        case .books:
            BookSearchScreen(onIdentified: onIdentified)
        case .anime:
            AnimeSearchScreen(onIdentified: onIdentified)
        case .manga:
            MangaSearchScreen(onIdentified: onIdentified)
        case .games:
            GameSearchScreen(onIdentified: onIdentified)
        case .albums:
            AlbumSearchScreen(onIdentified: onIdentified)
        case .custom:
            // Custom lists that opted into Maps lookup at create time
            // use the same Places picker as Restaurants/Bars, with an
            // unbiased search (`.any`). Items still get stamped with
            // category `.custom` so they render under custom-list
            // affordances elsewhere.
            if list.linksToMapsLocation {
                PlaceSearchScreen(
                    kind: .any,
                    stagedCategory: .custom,
                    onIdentified: onIdentified
                )
            } else {
                CustomItemFormScreen(list: list, onIdentified: onIdentified)
            }
        }
    }
}
