import Foundation

/// Canned-results implementation of `PlacesSearchService` used by previews,
/// snapshot tests, and (for now) the running app until live API keys exist.
struct MockPlacesSearchService: PlacesSearchService {

    /// Optional simulated network delay so the loading state is visible
    /// during preview iteration. Defaults to zero.
    var simulatedDelay: Duration = .zero

    func search(query: String, kind: PlacesSearchKind) async throws -> [PlaceSearchResult] {
        if simulatedDelay > .zero {
            try? await Task.sleep(for: simulatedDelay)
        }

        let pool: [PlaceSearchResult]
        switch kind {
        case .restaurant: pool = Self.restaurantPool
        case .bar:        pool = Self.barPool
        // Custom lists with the Maps toggle on search across all kinds.
        case .any:        pool = Self.restaurantPool + Self.barPool
        }

        guard !query.isEmpty else { return pool }

        let lower = query.lowercased()
        let filtered = pool.filter {
            $0.name.lowercased().contains(lower) || $0.address.lowercased().contains(lower)
        }
        // If nothing matches the query, return the full pool so the picker is
        // never empty in previews. The query is just an autocomplete hint.
        return filtered.isEmpty ? pool : filtered
    }

    private static let restaurantPool: [PlaceSearchResult] = [
        .init(
            id: "ChIJN1t_tDeuEmsRUsoyG83frY4",
            name: "Bestia",
            address: "2121 E 7th Pl, Los Angeles, CA",
            latitude: 34.0349,
            longitude: -118.2358,
            mapsURL: URL(string: "https://maps.google.com/?cid=12345")!
        ),
        .init(
            id: "ChIJ1234567890abcdef",
            name: "Kismet",
            address: "4648 Hollywood Blvd, Los Angeles, CA",
            latitude: 34.1016,
            longitude: -118.2912,
            mapsURL: URL(string: "https://maps.google.com/?cid=22222")!
        ),
        .init(
            id: "ChIJabcdef1234567890",
            name: "Sushi Note",
            address: "13447 Ventura Blvd, Sherman Oaks, CA",
            latitude: 34.1495,
            longitude: -118.4274,
            mapsURL: URL(string: "https://maps.google.com/?cid=33333")!
        ),
        .init(
            id: "ChIJplacefoo",
            name: "Gjelina",
            address: "1429 Abbot Kinney Blvd, Venice, CA",
            latitude: 33.9923,
            longitude: -118.4691,
            mapsURL: URL(string: "https://maps.google.com/?cid=44444")!
        ),
        .init(
            id: "ChIJplacebar",
            name: "Republique",
            address: "624 S La Brea Ave, Los Angeles, CA",
            latitude: 34.0633,
            longitude: -118.3441,
            mapsURL: URL(string: "https://maps.google.com/?cid=55555")!
        )
    ]

    private static let barPool: [PlaceSearchResult] = [
        .init(
            id: "ChIJbar1",
            name: "The Varnish",
            address: "118 E 6th St, Los Angeles, CA",
            latitude: 34.0454,
            longitude: -118.2495,
            mapsURL: URL(string: "https://maps.google.com/?cid=99001")!
        ),
        .init(
            id: "ChIJbar2",
            name: "Death & Co",
            address: "433 E 6th St, New York, NY",
            latitude: 40.7242,
            longitude: -73.9866,
            mapsURL: URL(string: "https://maps.google.com/?cid=99002")!
        ),
        .init(
            id: "ChIJbar3",
            name: "Attaboy",
            address: "134 Eldridge St, New York, NY",
            latitude: 40.7195,
            longitude: -73.9912,
            mapsURL: URL(string: "https://maps.google.com/?cid=99003")!
        )
    ]
}
