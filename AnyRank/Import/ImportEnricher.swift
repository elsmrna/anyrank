import Foundation

/// Fills in catalog metadata (artwork, canonical links, years) for queued
/// import items that arrived without it — a Letterboxd row, a pasted title.
///
/// Runs just in time, as an item comes up in the ranking spree, rather than
/// for the whole import up front: a 1,000-film export would otherwise mean
/// thousands of API calls before the user ranks anything.
///
/// Deliberately conservative: only an exact (normalized) title match with a
/// compatible year/creator is accepted. A wrong poster is worse than none.
struct ImportEnricher {
    let movies: any MovieSearchService
    var tv: any TVSearchService = MockTVSearchService()
    let books: any BookSearchService
    let anime: any AnimeSearchService
    var manga: any MangaSearchService = MockMangaSearchService()
    let games: any GameSearchService
    var boardGames: any BoardGameSearchService = MockBoardGameSearchService()
    let music: any MusicSearchService
    var bands: any ArtistSearchService = MockArtistSearchService()

    /// An enriched copy of `item`, or nil when there's nothing to add or no
    /// confident match.
    func enrich(_ item: StagedItem) async -> StagedItem? {
        let name = ImportMatcher.normalize(item.name)
        var updated = item
        do {
            switch item.category {
            case .movies where item.movie == nil:
                // An IMDb ID means an exact match — no title guessing.
                if let imdbID = item.imdbID {
                    guard let hit = try await movies.lookup(imdbID: imdbID) else { return nil }
                    updated.movie = hit
                    break
                }
                let results = try await movies.search(query: item.name)
                guard let hit = results.first(where: {
                    ImportMatcher.normalize($0.title) == name && yearsAgree($0.releaseYear, item.fallbackYear)
                }) else { return nil }
                updated.movie = hit

            case .tv where item.tv == nil:
                if let imdbID = item.imdbID {
                    guard let hit = try await tv.lookupShow(imdbID: imdbID) else { return nil }
                    updated.tv = hit
                    break
                }
                let results = try await tv.searchShows(query: item.name)
                guard let hit = results.first(where: {
                    ImportMatcher.normalize($0.title) == name && yearsAgree($0.firstAirYear, item.fallbackYear)
                }) else { return nil }
                updated.tv = hit

            case .books where item.book == nil || item.book?.coverURL == nil:
                let author = item.book?.author ?? item.fallbackCreator
                let results = try await books.search(query: item.name)
                guard let hit = results.first(where: {
                    ImportMatcher.normalize($0.title) == name && creatorsAgree($0.author, author)
                }) else { return nil }
                if let existing = item.book {
                    guard hit.coverURL != nil else { return nil }
                    updated.book = BookSearchResult(
                        id: existing.id, title: existing.title, author: existing.author,
                        publicationYear: existing.publicationYear ?? hit.publicationYear,
                        isbn: existing.isbn ?? hit.isbn,
                        storyGraphURL: existing.storyGraphURL ?? hit.storyGraphURL,
                        coverURL: hit.coverURL
                    )
                } else {
                    updated.book = hit
                }

            case .anime where item.anime == nil:
                let results = try await anime.search(query: item.name)
                guard let hit = results.first(where: { result in
                    ([result.title] + result.alternateTitles).contains { ImportMatcher.normalize($0) == name }
                        && yearsAgree(result.seasonYear, item.fallbackYear)
                }) else { return nil }
                updated.anime = hit

            case .manga where item.manga == nil:
                let results = try await manga.searchManga(query: item.name)
                guard let hit = results.first(where: { result in
                    ([result.title] + result.alternateTitles).contains { ImportMatcher.normalize($0) == name }
                        && yearsAgree(result.startYear, item.fallbackYear)
                }) else { return nil }
                updated.manga = hit

            case .games where item.game == nil:
                let results = try await games.search(query: item.name)
                guard let hit = results.first(where: {
                    ImportMatcher.normalize($0.name) == name && yearsAgree($0.firstReleaseYear, item.fallbackYear)
                }) else { return nil }
                updated.game = hit

            case .boardGames where item.boardGame == nil:
                let results = try await boardGames.searchBoardGames(query: item.name)
                guard let hit = results.first(where: {
                    ImportMatcher.normalize($0.name) == name && yearsAgree($0.yearPublished, item.fallbackYear)
                }) else { return nil }
                updated.boardGame = hit

            case .bands where item.band == nil:
                let results = try await bands.searchArtists(query: item.name)
                guard let hit = results.first(where: { ImportMatcher.normalize($0.name) == name }) else { return nil }
                updated.band = hit

            case .albums where item.album == nil:
                let results = try await music.searchAlbums(query: item.name)
                guard let hit = results.first(where: {
                    ImportMatcher.normalize($0.title) == name && creatorsAgree($0.artist, item.fallbackCreator)
                }) else { return nil }
                updated.album = hit

            default:
                // Places need sign-in and are too ambiguous by name alone;
                // custom items have no catalog.
                return nil
            }
        } catch {
            return nil
        }
        return updated == item ? nil : updated
    }

    private func yearsAgree(_ a: Int?, _ b: Int?) -> Bool {
        guard let a, let b else { return true }
        return abs(a - b) <= 1
    }

    private func creatorsAgree(_ a: String, _ b: String?) -> Bool {
        guard let b, !b.isEmpty else { return true }
        let x = ImportMatcher.normalize(a), y = ImportMatcher.normalize(b)
        return x.contains(y) || y.contains(x)
    }
}
