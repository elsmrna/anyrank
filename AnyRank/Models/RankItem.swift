import Foundation
import Observation

/// A ranked item in a `RankList`. Category-specific metadata is stored as
/// optional fields — for v1 the schemas are fixed and known, so optionals
/// on a single class are cleaner than polymorphism.
///
/// Each `RankItem` becomes one row in its list's CSV file. Custom-category
/// metadata expands to one `custom_<field>` column per field name defined
/// on the parent `RankList`.
@Observable
@MainActor
final class RankItem: Identifiable {

    let id: UUID
    var name: String

    /// Back-reference to the owning list. Set by `RankList.init` and by
    /// `RankList.append`-style mutations. Weak isn't needed because the
    /// reference cycle is intentional and lifecycle-managed by Repository.
    var list: RankList?

    var bucketRaw: String
    var score: Double
    var notes: String
    var dateConsumed: Date?
    var createdAt: Date

    // MARK: Restaurants & Bars metadata
    var placeID: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var mapsURLString: String?

    // MARK: Movies metadata
    var tmdbID: Int?
    /// Year of release/publication. Used by both Movies (release year) and
    /// Books (publication year). The CSV column is `release_year` for both.
    var releaseYear: Int?
    var posterURLString: String?
    var imdbURLString: String?

    // MARK: Books metadata
    var author: String?
    var isbn: String?
    var storyGraphURLString: String?
    /// Cover-art URL. Shared across Books (Open Library), Anime
    /// (AniList), and the future Music/Games categories — every
    /// visual-medium category can reuse this field for its thumbnail.
    var coverURLString: String?

    // MARK: Anime metadata
    /// AniList format: "TV", "MOVIE", "OVA", "SPECIAL", "ONA", "MUSIC".
    /// Stored as a String so new formats don't require a migration.
    var animeFormat: String?
    var episodeCount: Int?
    var aniListURLString: String?

    // MARK: Games metadata
    /// Platform abbreviations from IGDB — "PS5", "PC", "SW", etc. Kept
    /// as a plain array; CSV encodes it as a "|"-joined string. Order
    /// preserved.
    var platforms: [String]?
    var igdbURLString: String?

    // MARK: Music metadata (shared by Albums + Songs)
    /// Artist name — required for any Music item. Multi-artist tracks
    /// stored as a single string joined with ", " to keep the CSV
    /// dialect simple.
    var artist: String?
    /// Only meaningful for Songs — the album this track appears on.
    /// Nil for Albums.
    var albumTitle: String?
    /// Only meaningful for Songs. Nil for Albums.
    var durationSeconds: Int?
    var spotifyURLString: String?

    // MARK: Custom metadata
    var customLinkString: String?
    var customFieldValues: [String: String]

    var bucket: Bucket {
        get { Bucket(rawValue: bucketRaw) ?? .fine }
        set { bucketRaw = newValue.rawValue }
    }

    var primaryURL: URL? {
        let urlString: String?
        switch list?.category {
        case .restaurants, .bars: urlString = mapsURLString
        case .movies: urlString = imdbURLString
        case .books: urlString = storyGraphURLString
        case .anime: urlString = aniListURLString
        case .games: urlString = igdbURLString
        case .albums, .songs: urlString = spotifyURLString
        case .custom, .none:
            // Custom items can carry Maps metadata when the list opted
            // into `linksToMapsLocation`; prefer that as the canonical
            // link, falling back to the user-provided free-form link.
            urlString = mapsURLString ?? customLinkString
        }
        return urlString.flatMap { URL(string: $0) }
    }

    /// True iff the bucket containing this item has at least 3 members.
    /// Per Spec § 4, scores are not displayed below this threshold.
    var shouldDisplayScore: Bool {
        guard let list else { return false }
        return list.items(in: bucket).count >= 3
    }

    init(
        id: UUID = UUID(),
        name: String,
        bucket: Bucket,
        score: Double = 0.0,
        notes: String = "",
        dateConsumed: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bucketRaw = bucket.rawValue
        self.score = score
        self.notes = notes
        self.dateConsumed = dateConsumed
        self.createdAt = createdAt
        self.customFieldValues = [:]
    }
}
