import Foundation

/// A Google place's photo, referenced by place ID rather than by image URL.
///
/// Places photo URLs are signed and expire, so they can't be stored. The
/// place ID is stable and already saved on every place item, so artwork for
/// a place is the URL `places-photo://<place ID>`. `ArtworkCache` resolves
/// it through `loader` (the Places SDK when a key is configured) the first
/// time it's shown on a device, then keeps the thumbnail. Existing items get
/// photos without a migration, and a search never pays for photos it won't
/// show.
enum PlacePhotos {

    static let scheme = "places-photo"

    enum Fetch: Sendable {
        case image(Data)
        /// The place has no photos.
        case none
        /// A network or quota error. Worth retrying.
        case failed
    }

    /// Set at launch when the Places SDK is configured. Nil means place
    /// photos aren't available, and places show their placeholder.
    nonisolated(unsafe) static var loader: (@Sendable (String) async -> Fetch)?

    static func url(forPlaceID placeID: String?) -> String? {
        guard let placeID, !placeID.isEmpty,
              let encoded = placeID.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }
        return "\(scheme)://\(encoded)"
    }

    static func placeID(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return url.host(percentEncoded: false)
    }
}
