import Foundation

/// Canned bands for previews and tests (real Deezer IDs and photos).
struct MockArtistSearchService: ArtistSearchService {

    func searchArtists(query: String) async throws -> [ArtistSearchResult] {
        guard !query.isEmpty else { return Self.pool }
        let lower = query.lowercased()
        let filtered = Self.pool.filter { $0.name.lowercased().contains(lower) }
        return filtered.isEmpty ? Self.pool : filtered
    }

    static let pool: [ArtistSearchResult] = [
        artist(399, "Radiohead", 4_099_428, 45, "0d58cfbc90f2e776608bcdc0c45a4711"),
        artist(181, "Talking Heads", 446_905, 32, "cc36269657d82833d0d0f1432501e0d5"),
        artist(642, "LCD Soundsystem", 179_601, 36, "49e43774b5c3dcdfa045eb371d8ad35a"),
        artist(169, "Fleetwood Mac", 1_673_405, 56, "ef23278cf3a67a3ca8404ddaa38699d4"),
        artist(78668, "Bon Iver", 549_281, 16, "6edd41ee3cd3005077e07647242fb238"),
        artist(1_058_631, "Phoebe Bridgers", 208_003, 34, "aaf9a93b5b4dc7a2368d375201cc58e1"),
    ]

    private static func artist(_ id: Int, _ name: String, _ fans: Int, _ albums: Int, _ picture: String) -> ArtistSearchResult {
        ArtistSearchResult(
            id: id, name: name, fanCount: fans, albumCount: albums,
            imageURL: URL(string: "https://cdn-images.dzcdn.net/images/artist/\(picture)/250x250-000000-80-0-0.jpg"),
            deezerURL: URL(string: "https://www.deezer.com/artist/\(id)")
        )
    }
}
