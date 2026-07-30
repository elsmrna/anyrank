import Foundation

/// Canned results for both music methods. Used by previews, snapshot
/// tests, and as fallback when Spotify credentials aren't configured.
struct MockMusicSearchService: MusicSearchService {

    var simulatedDelay: Duration = .zero

    func searchAlbums(query: String) async throws -> [AlbumSearchResult] {
        if simulatedDelay > .zero { try? await Task.sleep(for: simulatedDelay) }
        return Self.filter(pool: Self.albumPool, query: query) { a, lower in
            a.title.lowercased().contains(lower) || a.artist.lowercased().contains(lower)
        }
    }

    func searchSongs(query: String) async throws -> [SongSearchResult] {
        if simulatedDelay > .zero { try? await Task.sleep(for: simulatedDelay) }
        return Self.filter(pool: Self.songPool, query: query) { s, lower in
            s.title.lowercased().contains(lower)
                || s.artist.lowercased().contains(lower)
                || (s.albumTitle?.lowercased().contains(lower) ?? false)
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

    private static let songPool: [SongSearchResult] = [
        .init(id: "mock-sng-1", title: "Nights", artist: "Frank Ocean",
              albumTitle: "Blonde", releaseYear: 2016, durationSeconds: 307,
              coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ")),
        .init(id: "mock-sng-2", title: "Dreams", artist: "Fleetwood Mac",
              albumTitle: "Rumours", releaseYear: 1977, durationSeconds: 257,
              coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/track/0ofHAoxe9vBkTCp2UQIavz")),
        .init(id: "mock-sng-3", title: "Alright", artist: "Kendrick Lamar",
              albumTitle: "To Pimp a Butterfly", releaseYear: 2015, durationSeconds: 219,
              coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/track/3iVcZ5G6tvkXZkZKlMpIUs")),
        .init(id: "mock-sng-4", title: "Weird Fishes/Arpeggi", artist: "Radiohead",
              albumTitle: "In Rainbows", releaseYear: 2007, durationSeconds: 318,
              coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/track/6MZbzKGKzqSjqiHBIWKZ26")),
        .init(id: "mock-sng-5", title: "So What", artist: "Miles Davis",
              albumTitle: "Kind of Blue", releaseYear: 1959, durationSeconds: 562,
              coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/track/4vLYewWIvqUfMaZWIsyMSy")),
        .init(id: "mock-sng-6", title: "Nuthin' but a 'G' Thang", artist: "Dr. Dre",
              albumTitle: "The Chronic", releaseYear: 1992, durationSeconds: 239,
              coverURL: nil, spotifyURL: URL(string: "https://open.spotify.com/track/6XyY86QOPPrYVGvF9ch6wz"))
    ]
}
