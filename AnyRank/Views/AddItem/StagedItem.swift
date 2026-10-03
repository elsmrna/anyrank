import Foundation

/// A would-be `RankItem` accumulated during the add-item flow but not yet
/// persisted to SwiftData. The coordinator holds a `StagedItem` from the
/// moment the item is identified through to the final apply step.
///
/// Per-category fields are optional and populated only when the matching
/// category was the source. The ID is generated once at construction time
/// so the comparison flow's `RankingSession` can reference the new item by
/// a stable UUID before SwiftData ever sees it.
struct StagedItem: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var category: Category

    // Restaurants / Bars / Stays
    var place: PlaceSearchResult?

    // Movies
    var movie: MovieSearchResult?

    // TV
    var tv: TVShowSearchResult?

    // Books
    var book: BookSearchResult?

    // Anime
    var anime: AnimeSearchResult?

    // Manga
    var manga: MangaSearchResult?

    // Games
    var game: GameSearchResult?

    // Music
    var album: AlbumSearchResult?

    // Custom
    var customLink: String?
    var customFieldValues: [String: String]

    // MARK: Import provenance
    //
    // Populated by importers (Steam, Letterboxd, …). All optional so items
    // staged through search are unaffected.

    /// Link to the item on the source service; becomes `sourceURLString`.
    var sourceURL: URL?
    /// Bucket the source's own rating points to. Shown as a hint on the
    /// bucket picker — never applied automatically.
    var suggestedBucket: Bucket?
    /// One line of context from the source, e.g. "212 hours played" or
    /// "Rated ★★★★ on Letterboxd".
    var sourceNote: String?
    var dateConsumed: Date?
    var notes: String?
    /// Year / creator known from the source when there's no full catalog
    /// record (e.g. a Letterboxd row before TMDB enrichment).
    var fallbackYear: Int?
    var fallbackCreator: String?
    /// IMDb title ID (`tt…`) when the source knows it — lets enrichment do
    /// an exact TMDB lookup and gives the item its IMDb link.
    var imdbID: String?

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
        if let tv {
            item.tmdbID = tv.id
            item.releaseYear = tv.firstAirYear
            item.seasonCount = tv.seasonCount
            item.posterURLString = tv.posterURL?.absoluteString
            item.imdbURLString = tv.imdbURL?.absoluteString
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
        if let manga {
            item.animeFormat = manga.format
            item.releaseYear = manga.startYear
            item.chapterCount = manga.chapterCount
            item.volumeCount = manga.volumeCount
            item.coverURLString = manga.coverURL?.absoluteString
            item.aniListURLString = manga.aniListURL?.absoluteString
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
        if let customLink {
            item.customLinkString = customLink
        }
        if !customFieldValues.isEmpty {
            item.customFieldValues = customFieldValues
        }
        if let sourceURL {
            item.sourceURLString = sourceURL.absoluteString
        }
        if item.imdbURLString == nil, let imdbID {
            item.imdbURLString = "https://www.imdb.com/title/\(imdbID)/"
        }
        if let dateConsumed {
            item.dateConsumed = dateConsumed
        }
        if let notes, !notes.isEmpty {
            item.notes = notes
        }
        if item.releaseYear == nil {
            item.releaseYear = fallbackYear
        }
        if let fallbackCreator, !fallbackCreator.isEmpty {
            switch category {
            case .books:
                if item.author == nil { item.author = fallbackCreator }
            case .albums:
                if item.artist == nil { item.artist = fallbackCreator }
            default:
                break
            }
        }
    }

    // MARK: Display

    /// Thumbnail for the not-yet-persisted item, mirroring
    /// `RankingApplier.comparisonImageURLString(for:in:)` for saved items.
    var artworkURLString: String? {
        switch category {
        case .movies: return movie?.posterURL?.absoluteString
        case .tv:     return tv?.posterURL?.absoluteString
        case .books:  return book?.coverURL?.absoluteString
        case .anime:  return anime?.coverURL?.absoluteString
        case .manga:  return manga?.coverURL?.absoluteString
        case .games:  return game?.coverURL?.absoluteString
        case .albums: return album?.coverURL?.absoluteString
        case .restaurants, .bars, .stays, .custom: return PlacePhotos.url(forPlaceID: place?.id)
        }
    }

    /// One-line supporting text — parallel to
    /// `RankingApplier.comparisonSecondaryText(for:in:)`.
    var secondaryText: String? {
        func joined(_ parts: [String?]) -> String? {
            let kept = parts.compactMap { $0 }.filter { !$0.isEmpty }
            return kept.isEmpty ? nil : kept.joined(separator: " · ")
        }
        let year = fallbackYear.map(String.init)
        switch category {
        case .movies:
            return (movie?.releaseYear).map(String.init) ?? year
        case .tv:
            guard let tv else { return year }
            return TVShowText.secondary(year: tv.firstAirYear, seasons: tv.seasonCount)
        case .books:
            guard let book else { return joined([fallbackCreator, year]) }
            return joined([book.author, book.publicationYear.map(String.init)])
        case .anime:
            guard let anime else { return year }
            return joined([
                anime.seasonYear.map(String.init),
                (anime.episodeCount ?? 0) > 1 ? "\(anime.episodeCount!) eps" : nil,
            ])
        case .manga:
            guard let manga else { return year }
            return joined([manga.format, manga.startYear.map(String.init), MangaLength.text(chapters: manga.chapterCount, volumes: manga.volumeCount)])
        case .games:
            guard let game else { return year }
            let platforms = GameSearchScreen.compactPlatforms(game.platforms)
            return joined([platforms, game.firstReleaseYear.map(String.init) ?? year])
        case .albums:
            guard let album else { return joined([fallbackCreator, year]) }
            return joined([album.artist, album.releaseYear.map(String.init)])
        case .restaurants, .bars, .stays, .custom:
            return place?.address
        }
    }

}
