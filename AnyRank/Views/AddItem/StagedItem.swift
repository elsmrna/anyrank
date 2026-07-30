import Foundation

/// A would-be `RankItem` accumulated during the add-item flow but not yet
/// persisted to SwiftData. The coordinator holds a `StagedItem` from the
/// moment the item is identified through to the final apply step.
///
/// Per-category fields are optional and populated only when the matching
/// category was the source. The ID is generated once at construction time
/// so the comparison flow's `RankingSession` can reference the new item by
/// a stable UUID before SwiftData ever sees it.
struct StagedItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var category: Category

    // Restaurants / Bars
    var place: PlaceSearchResult?

    // Movies
    var movie: MovieSearchResult?

    // Books
    var book: BookSearchResult?

    // Anime
    var anime: AnimeSearchResult?

    // Games
    var game: GameSearchResult?

    // Music
    var album: AlbumSearchResult?
    var song: SongSearchResult?

    // Custom
    var customLink: String?
    var customFieldValues: [String: String]

    init(id: UUID = UUID(), name: String, category: Category) {
        self.id = id
        self.name = name
        self.category = category
        self.customFieldValues = [:]
    }

    /// Populate a `RankItem`'s metadata fields from this staged record.
    /// Bucket and score are written separately by the apply step.
    ///
    /// `@MainActor` because `RankItem` is main-actor-isolated (it's an
    /// `@Observable @MainActor` model class) and every mutation below
    /// hits a MainActor-scoped property.
    @MainActor
    func apply(to item: RankItem) {
        item.name = name
        if let place {
            item.placeID = place.id
            item.address = place.address
            item.latitude = place.latitude
            item.longitude = place.longitude
            item.mapsURLString = place.mapsURL.absoluteString
        }
        if let movie {
            item.tmdbID = movie.id
            item.releaseYear = movie.releaseYear
            item.posterURLString = movie.posterURL?.absoluteString
            item.imdbURLString = movie.imdbURL?.absoluteString
        }
        if let book {
            item.author = book.author
            item.releaseYear = book.publicationYear
            item.isbn = book.isbn
            item.storyGraphURLString = book.storyGraphURL?.absoluteString
            item.coverURLString = book.coverURL?.absoluteString
        }
        if let anime {
            item.animeFormat = anime.format
            item.releaseYear = anime.seasonYear
            item.episodeCount = anime.episodeCount
            item.coverURLString = anime.coverURL?.absoluteString
            item.aniListURLString = anime.aniListURL?.absoluteString
        }
        if let game {
            item.platforms = game.platforms
            item.releaseYear = game.firstReleaseYear
            item.coverURLString = game.coverURL?.absoluteString
            item.igdbURLString = game.igdbURL?.absoluteString
        }
        if let album {
            item.artist = album.artist
            item.releaseYear = album.releaseYear
            item.coverURLString = album.coverURL?.absoluteString
            item.spotifyURLString = album.spotifyURL?.absoluteString
        }
        if let song {
            item.artist = song.artist
            item.albumTitle = song.albumTitle
            item.releaseYear = song.releaseYear
            item.durationSeconds = song.durationSeconds
            item.coverURLString = song.coverURL?.absoluteString
            item.spotifyURLString = song.spotifyURL?.absoluteString
        }
        if let customLink {
            item.customLinkString = customLink
        }
        if !customFieldValues.isEmpty {
            item.customFieldValues = customFieldValues
        }
    }
}
