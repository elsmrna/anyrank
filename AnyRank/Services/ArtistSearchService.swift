import Foundation

/// Result returned by a band/artist lookup. `id` is Deezer's artist ID.
struct ArtistSearchResult: Identifiable, Equatable, Hashable, Sendable, Codable {
    let id: Int
    let name: String
    let fanCount: Int?
    let albumCount: Int?
    let imageURL: URL?
    let deezerURL: URL?
}

protocol ArtistSearchService: Sendable {
    func searchArtists(query: String) async throws -> [ArtistSearchResult]
}

enum ArtistText {
    /// "4.1M fans", "446K fans", "812 fans". Fan count is the clearest way
    /// to tell two acts with the same name apart.
    static func fans(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        let number = count.formatted(.number.notation(.compactName).precision(.significantDigits(1...2)))
        return "\(number) fan\(count == 1 ? "" : "s")"
    }
}
