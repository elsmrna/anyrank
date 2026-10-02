import Foundation

/// Canned album results. Used by previews, snapshot
/// tests, and as fallback when Spotify credentials aren't configured.
struct MockMusicSearchService: MusicSearchService {

    var simulatedDelay: Duration = .zero

    func searchAlbums(query: String) async throws -> [AlbumSearchResult] {
        if simulatedDelay > .zero { try? await Task.sleep(for: simulatedDelay) }
        return Self.filter(pool: Self.albumPool, query: query) { a, lower in
            a.title.lowercased().contains(lower) || a.artist.lowercased().contains(lower)
        }
    }

    private static func filter<T>(pool: [T], query: String, predicate: (T, String) -> Bool) -> [T] {
        guard !query.isEmpty else { return pool }
        let lower = query.lowercased()
        let filtered = pool.filter { predicate($0, lower) }
        return filtered.isEmpty ? pool : filtered
    }

    private static let albumPool: [AlbumSearchResult] = [
        .init(id: "mock-alb-1", title: "Blonde", artist: "Frank Ocean",
              releaseYear: 2016, coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/album/3mH6qwIy9crq0I9YQbOuDf")),
        .init(id: "mock-alb-2", title: "Rumours", artist: "Fleetwood Mac",
              releaseYear: 1977, coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/album/1bt6q2SruMsBtcerNVtpZB")),
        .init(id: "mock-alb-3", title: "To Pimp a Butterfly", artist: "Kendrick Lamar",
              releaseYear: 2015, coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/album/7ycBtnsMtyVbbwTfJwRjSP")),
        .init(id: "mock-alb-4", title: "In Rainbows", artist: "Radiohead",
              releaseYear: 2007, coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/album/5vkqYmiPBYLaalcmjujWxK")),
        .init(id: "mock-alb-5", title: "Kind of Blue", artist: "Miles Davis",
              releaseYear: 1959, coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/album/1weenld61qoidwYuZ1GESA")),
        .init(id: "mock-alb-6", title: "The Chronic", artist: "Dr. Dre",
              releaseYear: 1992, coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/album/6MOyKzYrLzYUcnMKGmwCTV"))
    ]
}
