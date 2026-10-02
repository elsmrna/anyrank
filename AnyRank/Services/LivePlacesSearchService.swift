import Foundation
import GooglePlaces

/// Google Places-backed implementation of `PlacesSearchService`.
///
/// Two-stage flow per Places SDK best practice: `findAutocompletePredictions`
/// for the typeahead pass, then `fetchPlace` for each picked prediction to
/// resolve full coordinates and formatted address. Both calls share an
/// autocomplete session token so Google bills them as a single session
/// rather than per-keystroke.
///
/// Concurrency: the SDK's callback objects (`GMSAutocompletePrediction`,
/// `GMSPlace`) are not `Sendable`, and Swift 6 rightly refuses to let us
/// hand them across the continuation boundary. The bridge closures below
/// project each SDK object into a small Sendable value (`String` place IDs;
/// a `PlaceDetails` struct of coordinates and text) inside the callback
/// itself, then resume with that. Downstream code never touches an
/// unsandboxed SDK reference.
///
/// Threading: the SDK throws `GMSThreadException` unless its methods are
/// called on the main thread, so every bridge below is `@MainActor`.
/// Callers can be anywhere (search runs from a view task, Find from the
/// map, photos from `ArtworkCache`); the `await` hops to main.
///
/// Configuration: `GooglePlacesBootstrap.configure()` must have been
/// called once at app startup with a valid API key. If the key was
/// missing, `AnyRankApp` should be wiring `MockPlacesSearchService`
/// instead of this type.
final class LivePlacesSearchService: PlacesSearchService, @unchecked Sendable {

    /// Session token shared across calls within a single search session.
    /// Reusing it is the difference between paying per-keystroke and
    /// paying per-session for autocomplete.
    private let session = GMSAutocompleteSessionToken.init()

    func search(query: String, kind: PlacesSearchKind) async throws -> [PlaceSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let placeIDs = try await findPredictionIDs(query: trimmed, kind: kind)

        // Sequential — autocomplete typically returns 5 predictions, the
        // detail calls are fast, and going sequential sidesteps having to
        // batch-schedule callbacks. Cap fan-out defensively.
        var results: [PlaceSearchResult] = []
        results.reserveCapacity(min(placeIDs.count, 8))
        for placeID in placeIDs.prefix(8) {
            if let details = try? await fetchDetails(placeID: placeID) {
                results.append(details.toSearchResult())
            }
        }
        return results
    }

    // MARK: - Photos

    /// The place's first photo, at most 480px on its long edge, for
    /// `PlacePhotos.loader`. Two billed requests (place details with the
    /// photos field, then the photo itself), made once per place per device
    /// thanks to `ArtworkCache`. Not part of an autocomplete session.
    @MainActor
    static func photo(forPlaceID placeID: String) async -> PlacePhotos.Fetch {
        await withCheckedContinuation { continuation in
            let request = GMSFetchPlaceRequest(
                placeID: placeID,
                placeProperties: [GMSPlaceProperty.photos.rawValue],
                sessionToken: nil
            )
            GMSPlacesClient.shared().fetchPlace(with: request) { place, error in
                if error != nil {
                    continuation.resume(returning: .failed)
                    return
                }
                guard let metadata = place?.photos?.first else {
                    continuation.resume(returning: .none)
                    return
                }
                let photoRequest = GMSFetchPhotoRequest(photoMetadata: metadata, maxSize: CGSize(width: 480, height: 480))
                GMSPlacesClient.shared().fetchPhoto(with: photoRequest) { image, error in
                    if let data = image?.jpegData(compressionQuality: 0.85) {
                        continuation.resume(returning: .image(data))
                    } else {
                        continuation.resume(returning: error == nil ? .none : .failed)
                    }
                }
            }
        }
    }

    // MARK: - SDK bridges

    /// Returns place IDs only. Bridging `[GMSAutocompletePrediction]` out
    /// of the callback would violate Sendable — extract the `String`
    /// place ID inside the callback instead.
    @MainActor
    private func findPredictionIDs(query: String, kind: PlacesSearchKind) async throws -> [String] {
        let filter = GMSAutocompleteFilter()
        // Bias by establishment type when the list has one — Places'
        // "types" filter narrows suggestions to the relevant kind so a
        // search for "the v" in a Bars list doesn't suggest "The Village
        // School." Custom lists with the Maps toggle on use `.any` and
        // skip the filter entirely.
        if let filterType = kind.placesTypeFilter {
            filter.types = [filterType]
        }

        let token = session
        return try await withCheckedThrowingContinuation { continuation in
            GMSPlacesClient.shared().findAutocompletePredictions(
                fromQuery: query,
                filter: filter,
                sessionToken: token
            ) { predictions, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    let ids = (predictions ?? []).map(\.placeID)
                    continuation.resume(returning: ids)
                }
            }
        }
    }

    /// Returns a `PlaceDetails` snapshot rather than the raw `GMSPlace`.
    /// Same Sendable rationale as `findPredictionIDs` — copy the fields
    /// we need out of the SDK object inside the callback so nothing
    /// non-Sendable ever crosses the continuation.
    @MainActor
    private func fetchDetails(placeID: String) async throws -> PlaceDetails? {
        // Only fetch the fields we actually use — the SDK bills per-field.
        let fields: GMSPlaceField = [.placeID, .name, .formattedAddress, .coordinate]
        let token = session

        return try await withCheckedThrowingContinuation { continuation in
            GMSPlacesClient.shared().fetchPlace(
                fromPlaceID: placeID,
                placeFields: fields,
                sessionToken: token
            ) { place, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let place, let name = place.name else {
                    continuation.resume(returning: nil)
                    return
                }
                let details = PlaceDetails(
                    placeID: placeID,
                    name: name,
                    address: place.formattedAddress ?? "",
                    latitude: place.coordinate.latitude,
                    longitude: place.coordinate.longitude
                )
                continuation.resume(returning: details)
            }
        }
    }
}

// MARK: - Sendable value type

/// Sendable projection of the fields we need from `GMSPlace`. Existing
/// only so we can carry the SDK's result across the async boundary
/// without triggering Swift 6's strict-concurrency checks.
private struct PlaceDetails: Sendable {
    let placeID: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    func toSearchResult() -> PlaceSearchResult {
        // Canonical Maps URL by place ID. The Places API doesn't return
        // this directly, but the `?api=1&query=…&query_place_id=…` form
        // is the documented stable shape and opens the Maps app on iOS.
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mapsURL = URL(
            string: "https://www.google.com/maps/search/?api=1"
                + "&query=\(encodedName)"
                + "&query_place_id=\(placeID)"
        )
            ?? URL(string: "https://maps.google.com/")!

        return PlaceSearchResult(
            id: placeID,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            mapsURL: mapsURL
        )
    }
}

private extension PlacesSearchKind {
    /// The Places type filter that biases autocomplete to the right kind
    /// of place. Restaurants and bars both have first-class types in the
    /// Places taxonomy. Custom lists searching for arbitrary places
    /// (`.any`) return nil so the SDK applies no type bias.
    var placesTypeFilter: String? {
        switch self {
        case .restaurant: return "restaurant"
        case .bar:        return "bar"
        case .lodging:    return "lodging"
        case .any:        return nil
        }
    }
}
