import SwiftUI

/// Environment plumbing for service dependencies. Views read services via
/// `@Environment(\.placesService)` etc., which lets previews and tests
/// inject mocks without modifying view code.

private struct PlacesServiceKey: EnvironmentKey {
    static let defaultValue: any PlacesSearchService = MockPlacesSearchService()
}

private struct MovieServiceKey: EnvironmentKey {
    static let defaultValue: any MovieSearchService = MockMovieSearchService()
}

private struct TVServiceKey: EnvironmentKey {
    static let defaultValue: any TVSearchService = MockTVSearchService()
}

private struct BookServiceKey: EnvironmentKey {
    static let defaultValue: any BookSearchService = MockBookSearchService()
}

private struct AnimeServiceKey: EnvironmentKey {
    static let defaultValue: any AnimeSearchService = MockAnimeSearchService()
}

private struct MangaServiceKey: EnvironmentKey {
    static let defaultValue: any MangaSearchService = MockMangaSearchService()
}

private struct GameServiceKey: EnvironmentKey {
    static let defaultValue: any GameSearchService = MockGameSearchService()
}

private struct BoardGameServiceKey: EnvironmentKey {
    static let defaultValue: any BoardGameSearchService = MockBoardGameSearchService()
}

private struct ArtistServiceKey: EnvironmentKey {
    static let defaultValue: any ArtistSearchService = MockArtistSearchService()
}

private struct MusicServiceKey: EnvironmentKey {
    static let defaultValue: any MusicSearchService = MockMusicSearchService()
}

extension EnvironmentValues {
    var placesService: any PlacesSearchService {
        get { self[PlacesServiceKey.self] }
        set { self[PlacesServiceKey.self] = newValue }
    }
    var movieService: any MovieSearchService {
        get { self[MovieServiceKey.self] }
        set { self[MovieServiceKey.self] = newValue }
    }
    var tvService: any TVSearchService {
        get { self[TVServiceKey.self] }
        set { self[TVServiceKey.self] = newValue }
    }
    var bookService: any BookSearchService {
        get { self[BookServiceKey.self] }
        set { self[BookServiceKey.self] = newValue }
    }
    var animeService: any AnimeSearchService {
        get { self[AnimeServiceKey.self] }
        set { self[AnimeServiceKey.self] = newValue }
    }
    var mangaService: any MangaSearchService {
        get { self[MangaServiceKey.self] }
        set { self[MangaServiceKey.self] = newValue }
    }
    var gameService: any GameSearchService {
        get { self[GameServiceKey.self] }
        set { self[GameServiceKey.self] = newValue }
    }
    var boardGameService: any BoardGameSearchService {
        get { self[BoardGameServiceKey.self] }
        set { self[BoardGameServiceKey.self] = newValue }
    }
    var artistService: any ArtistSearchService {
        get { self[ArtistServiceKey.self] }
        set { self[ArtistServiceKey.self] = newValue }
    }
    var musicService: any MusicSearchService {
        get { self[MusicServiceKey.self] }
        set { self[MusicServiceKey.self] = newValue }
    }
}
