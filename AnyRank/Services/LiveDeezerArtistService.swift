import Foundation

/// Deezer-backed `ArtistSearchService`.
///
/// Deezer's public API needs no key or sign-in for search, so this is
/// injected unconditionally (like Open Library and AniList). One call:
/// `GET https://api.deezer.com/search/artist?q=…`, which returns the
/// artist's photo, fan count, and album count. Results come back ordered by
/// Deezer's relevance, which already favors the better-known act.
struct LiveDeezerArtistService: ArtistSearchService {

    private static let resultLimit = 15
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchArtists(query: String) async throws -> [ArtistSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.deezer.com/search/artist")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "\(Self.resultLimit)"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveServiceError.notImplemented("Deezer HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(DeezerArtistSearch.self, from: data)
        if let error = decoded.error {
            // Deezer reports quota and other errors in a 200 body.
            throw LiveServiceError.notImplemented("Deezer \(error.type ?? "error")")
        }
        return (decoded.data ?? []).map { artist in
            ArtistSearchResult(
                id: artist.id,
                name: artist.name,
                fanCount: artist.nb_fan,
                albumCount: artist.nb_album,
                imageURL: artist.picture_medium.flatMap(URL.init(string:)),
                deezerURL: artist.link.flatMap(URL.init(string:))
            )
        }
    }
}

private struct DeezerArtistSearch: Decodable {
    let data: [Artist]?
    let error: DeezerError?

    struct Artist: Decodable {
        let id: Int
        let name: String
        let nb_fan: Int?
        let nb_album: Int?
        let picture_medium: String?
        let link: String?
    }

    struct DeezerError: Decodable {
        let type: String?
    }
}
