import Foundation

/// Factories that produce in-memory `Repository` instances pre-seeded with
/// sample data, for use in `#Preview` blocks and snapshot tests.
///
/// Each factory creates an isolated `Repository` backed by `MemoryListStorage`.
/// Calling a factory multiple times produces independent state.
@MainActor
enum PreviewSupport {

    // MARK: Repositories

    /// Repository with no lists. Useful for empty-state previews.
    static func emptyRepository() -> Repository {
        makeRepository(seed: { _ in })
    }

    /// One restaurants list with three Loved items — exercises the
    /// "all in one bucket" rendering path.
    static func smallRestaurantsRepository() -> Repository {
        makeRepository { repo in
            let list = RankList(name: "Restaurants", category: .restaurants)
            seedItems(in: list, items: [
                ("Bestia", .loved, "2121 E 7th Pl, Los Angeles, CA"),
                ("Kismet", .loved, "4648 Hollywood Blvd, Los Angeles, CA"),
                ("Sushi Note", .loved, "13447 Ventura Blvd, Sherman Oaks, CA"),
            ])
            repo.addList(list)
        }
    }

    /// One restaurants list with items spanning all four buckets.
    static func fullRestaurantsRepository() -> Repository {
        makeRepository { repo in
            let list = RankList(name: "Restaurants — LA", category: .restaurants)
            seedItems(in: list, items: [
                ("Bestia", .loved, "2121 E 7th Pl, Los Angeles, CA"),
                ("Kismet", .loved, "4648 Hollywood Blvd, Los Angeles, CA"),
                ("Republique", .loved, "624 S La Brea Ave, Los Angeles, CA"),
                ("Gjelina", .liked, "1429 Abbot Kinney Blvd, Venice, CA"),
                ("Sushi Note", .liked, "13447 Ventura Blvd, Sherman Oaks, CA"),
                ("Joe's Diner", .fine, "100 Main St, Los Angeles, CA"),
                ("Tourist Trap", .didntLike, "Hollywood & Highland"),
            ])
            repo.addList(list)
        }
    }

    /// Single-item list — exercises the "no score until 3 items" rule.
    static func singleItemRepository() -> Repository {
        makeRepository { repo in
            let list = RankList(name: "Restaurants", category: .restaurants)
            seedItems(in: list, items: [
                ("Bestia", .loved, "2121 E 7th Pl, Los Angeles, CA"),
            ])
            repo.addList(list)
        }
    }

    /// Four lists across four categories — exercises the home view's
    /// grouped layout including Books.
    static func multipleListsRepository() -> Repository {
        makeRepository { repo in
            let restaurants = RankList(name: "Restaurants — LA", category: .restaurants)
            seedItems(in: restaurants, items: [
                ("Bestia", .loved, "2121 E 7th Pl"),
                ("Kismet", .loved, "4648 Hollywood Blvd"),
                ("Republique", .liked, "624 S La Brea"),
            ])
            repo.addList(restaurants)

            let bars = RankList(name: "Bars — Downtown", category: .bars)
            seedItems(in: bars, items: [
                ("The Varnish", .loved, "118 E 6th St"),
                ("Death & Co", .liked, "433 E 6th St"),
            ])
            repo.addList(bars)

            let movies = RankList(name: "Movies", category: .movies)
            seedMovies(in: movies, items: [
                ("Inception", .loved, 2010),
                ("The Dark Knight", .loved, 2008),
                ("Pulp Fiction", .liked, 1994),
            ])
            repo.addList(movies)

            let books = RankList(name: "Books", category: .books)
            seedBooks(in: books, items: [
                ("Beloved", "Toni Morrison", .loved, 1987),
                ("Pachinko", "Min Jin Lee", .loved, 2017),
                ("The Three-Body Problem", "Liu Cixin", .liked, 2008),
            ])
            repo.addList(books)
        }
    }

    /// One Custom list with `linksToMapsLocation == true` — exercises
    /// the "custom list backed by Google Maps" path so previews and
    /// snapshots can render the place-bearing custom item layout.
    static func customMapsLinkedRepository() -> Repository {
        makeRepository { repo in
            let list = RankList(
                name: "Weekend Spots",
                category: .custom,
                customFieldNames: ["Vibe"],
                linksToMapsLocation: true
            )
            seedItems(in: list, items: [
                ("Griffith Observatory", .loved, "2800 E Observatory Rd, Los Angeles, CA"),
                ("The Last Bookstore", .loved, "453 S Spring St, Los Angeles, CA"),
                ("Echo Park Lake", .liked, "751 Echo Park Ave, Los Angeles, CA"),
            ])
            // Custom items can still carry custom field values alongside
            // the Maps metadata — populate one to make that visible in
            // the detail-view preview.
            list.items.first?.customFieldValues = ["Vibe": "Touristy but worth it"]
            repo.addList(list)
        }
    }

    /// One albums list spanning two buckets — for previewing the
    /// Albums path with realistic artist strings.
    static func albumsRepository() -> Repository {
        makeRepository { repo in
            let list = RankList(name: "Albums — All-time", category: .albums)
            seedAlbums(in: list, items: [
                ("Blonde", "Frank Ocean", 2016, .loved),
                ("Rumours", "Fleetwood Mac", 1977, .loved),
                ("To Pimp a Butterfly", "Kendrick Lamar", 2015, .loved),
                ("In Rainbows", "Radiohead", 2007, .liked),
                ("Kind of Blue", "Miles Davis", 1959, .liked),
            ])
            repo.addList(list)
        }
    }

    /// One games list spanning two buckets — for previewing the Games
    /// path with realistic platform strings.
    static func gamesRepository() -> Repository {
        makeRepository { repo in
            let games = RankList(name: "Games — All-time", category: .games)
            seedGames(in: games, items: [
                ("The Witcher 3: Wild Hunt", ["PC", "PS4", "PS5", "XONE", "SW"], 2015, .loved),
                ("Elden Ring", ["PC", "PS5", "XSX"], 2022, .loved),
                ("Hades", ["PC", "SW", "PS5"], 2020, .loved),
                ("Cyberpunk 2077", ["PC", "PS5", "XSX"], 2020, .liked),
                ("Breath of the Wild", ["SW"], 2017, .liked),
            ])
            repo.addList(games)
        }
    }

    /// One anime list — TV shows + one movie — spanning two buckets.
    /// For previewing the Anime path.
    static func animeRepository() -> Repository {
        makeRepository { repo in
            let anime = RankList(name: "Anime — All-time", category: .anime)
            seedAnime(in: anime, items: [
                ("Cowboy Bebop", "TV", 1998, 26, .loved),
                ("Fullmetal Alchemist: Brotherhood", "TV", 2009, 64, .loved),
                ("Spirited Away", "MOVIE", 2001, 1, .loved),
                ("Attack on Titan", "TV", 2013, 25, .liked),
                ("Neon Genesis Evangelion", "TV", 1995, 26, .liked),
            ])
            repo.addList(anime)
        }
    }

    /// One manga list from the mock catalog, spanning two buckets.
    static func mangaRepository() -> Repository {
        makeRepository { repo in
            let manga = RankList(name: "Manga", category: .manga)
            let pool = Dictionary(uniqueKeysWithValues: MockMangaSearchService.pool.map { ($0.title, $0) })
            seedStaged(in: manga, items: [
                ("Vagabond", .loved), ("Monster", .loved), ("Berserk", .loved),
                ("Goodnight Punpun", .liked), ("Solo Leveling", .fine),
            ].compactMap { title, bucket in
                pool[title].map { result in
                    var staged = StagedItem(name: result.title, category: .manga)
                    staged.manga = result
                    return (staged, bucket)
                }
            })
            repo.addList(manga)
        }
    }

    /// One Stays list of LA hotels from the mock Places catalog.
    static func staysRepository() -> Repository {
        makeRepository { repo in
            let stays = RankList(name: "Stays — LA", category: .stays)
            let buckets: [Bucket] = [.loved, .loved, .liked, .liked, .fine]
            seedStaged(in: stays, items: zip(MockPlacesSearchService.lodgingPool, buckets).map { place, bucket in
                var staged = StagedItem(name: place.name, category: .stays)
                staged.place = place
                return (staged, bucket)
            })
            repo.addList(stays)
        }
    }

    /// One books list spanning two buckets — for previewing Books detail
    /// and snapshot tests that focus on the books path.
    static func booksRepository() -> Repository {
        makeRepository { repo in
            let books = RankList(name: "Books — 2024", category: .books)
            seedBooks(in: books, items: [
                ("Beloved", "Toni Morrison", .loved, 1987),
                ("Pachinko", "Min Jin Lee", .loved, 2017),
                ("Mrs Dalloway", "Virginia Woolf", .loved, 1925),
                ("The Three-Body Problem", "Liu Cixin", .liked, 2008),
                ("A Brief History of Time", "Stephen Hawking", .liked, 1988),
                ("The Great Gatsby", "F. Scott Fitzgerald", .fine, 1925),
            ])
            repo.addList(books)
        }
    }

    // MARK: Helpers

    private static func makeRepository(
        seed: @MainActor (Repository) -> Void
    ) -> Repository {
        let repo = Repository(storage: MemoryListStorage())
        seed(repo)
        return repo
    }

    private static func seedItems(
        in list: RankList,
        items: [(name: String, bucket: Bucket, address: String)]
    ) {
        let grouped = Dictionary(grouping: items.enumerated(), by: { $0.element.bucket })
        for (bucket, entries) in grouped {
            let count = entries.count
            for (rank, (_, payload)) in entries.enumerated() {
                let item = RankItem(
                    name: payload.name,
                    bucket: bucket,
                    score: ScoreInterpolation.score(forRankIndex: rank, bucketCount: count, bucket: bucket)
                )
                item.address = payload.address
                item.mapsURLString = "https://maps.google.com/?q=\(payload.name.replacingOccurrences(of: " ", with: "+"))"
                item.list = list
                list.items.append(item)
            }
        }
    }

    private static func seedMovies(
        in list: RankList,
        items: [(title: String, bucket: Bucket, year: Int)]
    ) {
        let grouped = Dictionary(grouping: items.enumerated(), by: { $0.element.bucket })
        for (bucket, entries) in grouped {
            let count = entries.count
            for (rank, (_, payload)) in entries.enumerated() {
                let item = RankItem(
                    name: payload.title,
                    bucket: bucket,
                    score: ScoreInterpolation.score(forRankIndex: rank, bucketCount: count, bucket: bucket)
                )
                item.releaseYear = payload.year
                item.imdbURLString = "https://www.imdb.com/title/tt\(1000000 + payload.year)/"
                item.list = list
                list.items.append(item)
            }
        }
    }

    private static func seedAlbums(
        in list: RankList,
        items: [(title: String, artist: String, year: Int, bucket: Bucket)]
    ) {
        let grouped = Dictionary(grouping: items.enumerated(), by: { $0.element.bucket })
        for (bucket, entries) in grouped {
            let count = entries.count
            for (rank, (_, payload)) in entries.enumerated() {
                let item = RankItem(
                    name: payload.title,
                    bucket: bucket,
                    score: ScoreInterpolation.score(forRankIndex: rank, bucketCount: count, bucket: bucket)
                )
                item.artist = payload.artist
                item.releaseYear = payload.year
                item.spotifyURLString = "https://open.spotify.com/album/mock-\(payload.title.hashValue.magnitude)"
                item.list = list
                list.items.append(item)
            }
        }
    }

    private static func seedGames(
        in list: RankList,
        items: [(name: String, platforms: [String], year: Int, bucket: Bucket)]
    ) {
        let grouped = Dictionary(grouping: items.enumerated(), by: { $0.element.bucket })
        for (bucket, entries) in grouped {
            let count = entries.count
            for (rank, (_, payload)) in entries.enumerated() {
                let item = RankItem(
                    name: payload.name,
                    bucket: bucket,
                    score: ScoreInterpolation.score(forRankIndex: rank, bucketCount: count, bucket: bucket)
                )
                item.platforms = payload.platforms
                item.releaseYear = payload.year
                item.igdbURLString = "https://www.igdb.com/games/mock-\(payload.name.hashValue.magnitude)"
                item.list = list
                list.items.append(item)
            }
        }
    }

    /// Items built from staged search results, the same way the add flow
    /// builds them, scored by position within each bucket.
    private static func seedStaged(in list: RankList, items: [(staged: StagedItem, bucket: Bucket)]) {
        let grouped = Dictionary(grouping: items, by: \.bucket)
        for (bucket, entries) in grouped {
            for (rank, entry) in entries.enumerated() {
                let item = RankItem(
                    name: entry.staged.name,
                    bucket: bucket,
                    score: ScoreInterpolation.score(forRankIndex: rank, bucketCount: entries.count, bucket: bucket)
                )
                entry.staged.apply(to: item)
                item.list = list
                list.items.append(item)
            }
        }
    }

    private static func seedAnime(
        in list: RankList,
        items: [(title: String, format: String, year: Int, episodes: Int, bucket: Bucket)]
    ) {
        let grouped = Dictionary(grouping: items.enumerated(), by: { $0.element.bucket })
        for (bucket, entries) in grouped {
            let count = entries.count
            for (rank, (_, payload)) in entries.enumerated() {
                let item = RankItem(
                    name: payload.title,
                    bucket: bucket,
                    score: ScoreInterpolation.score(forRankIndex: rank, bucketCount: count, bucket: bucket)
                )
                item.animeFormat = payload.format
                item.releaseYear = payload.year
                item.episodeCount = payload.episodes
                item.aniListURLString = "https://anilist.co/anime/mock-\(payload.title.hashValue.magnitude)"
                item.list = list
                list.items.append(item)
            }
        }
    }

    private static func seedBooks(
        in list: RankList,
        items: [(title: String, author: String, bucket: Bucket, year: Int)]
    ) {
        let grouped = Dictionary(grouping: items.enumerated(), by: { $0.element.bucket })
        for (bucket, entries) in grouped {
            let count = entries.count
            for (rank, (_, payload)) in entries.enumerated() {
                let item = RankItem(
                    name: payload.title,
                    bucket: bucket,
                    score: ScoreInterpolation.score(forRankIndex: rank, bucketCount: count, bucket: bucket)
                )
                item.author = payload.author
                item.releaseYear = payload.year
                let slug = payload.title
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                item.storyGraphURLString = "https://app.thestorygraph.com/books/\(slug)"
                item.list = list
                list.items.append(item)
            }
        }
    }
}
