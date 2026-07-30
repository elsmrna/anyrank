import Foundation
import GooglePlaces

/// One-time provisioning of the Google Places SDK's shared `GMSPlacesClient`
/// with the API key from `Secrets`. Called from `AnyRankApp.init`.
///
/// Returns the key that was provided so the caller can decide whether to
/// hand `LivePlacesSearchService` or `MockPlacesSearchService` into the
/// environment. Returns nil when the key is missing — that's the "fall
/// back to mock" signal.
enum GooglePlacesBootstrap {

    @discardableResult
    static func configure() -> String? {
        guard let key = Secrets.googlePlacesAPIKey else { return nil }
        GMSPlacesClient.provideAPIKey(key)
        return key
    }
}
