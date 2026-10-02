import Foundation

extension RankList {
    /// Lists whose items are places: Restaurants, Bars, Stays, and Custom lists
    /// that look items up on Google Maps.
    var isPlaceList: Bool {
        switch category {
        case .restaurants, .bars, .stays: return true
        case .custom: return linksToMapsLocation
        default: return false
        }
    }

    var placesSearchKind: PlacesSearchKind {
        switch category {
        case .restaurants: return .restaurant
        case .bars: return .bar
        case .stays: return .lodging
        default: return .any
        }
    }
}

/// Finds coordinates for a place list's items that don't have any yet (a
/// pasted import, or a Custom list from before Maps lookup was turned on),
/// so they can show on the list's map.
///
/// Conservative like `ImportEnricher`: a result is only used when its name
/// matches the item's exactly (after normalizing). A pin in the wrong
/// place is worse than no pin.
enum PlaceBackfill {

    /// The result to use for `name`, if any.
    static func match(for name: String, in results: [PlaceSearchResult]) -> PlaceSearchResult? {
        let wanted = ImportMatcher.normalize(name)
        return results.first { ImportMatcher.normalize($0.name) == wanted }
    }

    /// Looks up every item in `list` without coordinates and fills in the
    /// ones it can. Returns how many were found.
    @MainActor
    static func run(on list: RankList, using service: any PlacesSearchService, repository: Repository) async -> Int {
        var found = 0
        for item in list.items where item.latitude == nil || item.longitude == nil {
            let query = [item.name, item.address].compactMap { $0 }.joined(separator: " ")
            guard let results = try? await service.search(query: query, kind: list.placesSearchKind),
                  let hit = match(for: item.name, in: results)
            else { continue }
            item.placeID = hit.id
            item.address = hit.address
            item.latitude = hit.latitude
            item.longitude = hit.longitude
            item.mapsURLString = hit.mapsURL.absoluteString
            found += 1
        }
        if found > 0 { repository.touch(list) }
        return found
    }
}
