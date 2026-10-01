import Foundation

/// Result returned by a place lookup. Used to populate `RankItem`'s
/// Restaurants/Bars metadata fields.
struct PlaceSearchResult: Identifiable, Equatable, Hashable, Sendable, Codable {
    let id: String           // Google Places place_id
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    /// Canonical Google Maps URL for opening in the Maps app.
    let mapsURL: URL
}

/// Async search for places. The Restaurants and Bars categories both use
/// this — callers supply a hint (e.g. "restaurants" or "bars") to bias
/// the results. The mock implementation ignores the hint.
protocol PlacesSearchService: Sendable {
    func search(query: String, kind: PlacesSearchKind) async throws -> [PlaceSearchResult]
}

enum PlacesSearchKind: String, Sendable {
    case restaurant
    case bar
    /// No type filter — used by custom lists that opt into Maps lookup
    /// via `RankList.linksToMapsLocation`. Returns whatever the Places
    /// SDK considers most relevant for the query.
    case any
}
