import XCTest
@testable import AnyRank

final class LetterboxdZipTests: XCTestCase {

    /// Zips a folder the way iOS does (NSFileCoordinator .forUploading),
    /// so the reader is tested against real deflate output.
    private func makeZip(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("letterboxd-export")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        var zipURL: URL?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: .forUploading, error: &coordinationError) { url in
            let copy = dir.deletingLastPathComponent().appendingPathComponent("export.zip")
            try? FileManager.default.copyItem(at: url, to: copy)
            zipURL = copy
        }
        if let coordinationError { throw coordinationError }
        return try XCTUnwrap(zipURL)
    }

    func test_wholeExportZip_mergesFilesPerFilm() throws {
        let zip = try makeZip([
            "watched.csv": """
            Date,Name,Year,Letterboxd URI
            2024-01-01,Past Lives,2023,https://boxd.it/film-pl
            2024-01-02,Dune,2021,https://boxd.it/film-dune
            2024-01-03,Aftersun,2022,https://boxd.it/film-as
            """,
            "ratings.csv": """
            Date,Name,Year,Letterboxd URI,Rating
            2024-02-01,Past Lives,2023,https://boxd.it/film-pl,5
            2024-02-02,Dune,2021,https://boxd.it/film-dune,3.5
            """,
            "diary.csv": """
            Date,Name,Year,Letterboxd URI,Rating,Rewatch,Tags,Watched Date
            2024-01-01,Past Lives,2023,https://boxd.it/entry-1,4,,,2023-12-30
            2024-03-01,Past Lives,2023,https://boxd.it/entry-2,5,Yes,,2024-02-28
            """,
            "reviews.csv": """
            Date,Name,Year,Letterboxd URI,Rating,Rewatch,Review,Tags,Watched Date
            2024-03-01,Past Lives,2023,https://boxd.it/entry-2,5,Yes,Wrecked me.,,2024-02-28
            """,
            "watchlist.csv": """
            Date,Name,Year,Letterboxd URI
            2024-01-01,Oppenheimer,2023,https://boxd.it/film-opp
            """,
        ])
        let files = try FileImporters.ImportFile.load(from: zip)
        XCTAssertEqual(FileImporters.detect(files), .letterboxd)

        let candidates = try FileImporters.letterboxd(files)
        XCTAssertEqual(Set(candidates.map(\.item.name)), ["Past Lives", "Dune", "Aftersun"], "watchlist skipped")
        let pastLives = try XCTUnwrap(candidates.first { $0.item.name == "Past Lives" }?.item)
        XCTAssertEqual(pastLives.sourceURL?.absoluteString, "https://boxd.it/film-pl", "film link, not a diary entry")
        XCTAssertEqual(pastLives.suggestedBucket, .loved)
        XCTAssertEqual(pastLives.notes, "Wrecked me.")
        XCTAssertEqual(pastLives.dateConsumed, FileImporters.parseDate("2024-02-28"))
        XCTAssertEqual(candidates.first { $0.item.name == "Dune" }?.item.suggestedBucket, .liked)
        XCTAssertNil(candidates.first { $0.item.name == "Aftersun" }?.item.suggestedBucket)
        XCTAssertEqual(candidates.first?.item.name, "Past Lives", "highest rated first")
    }

    func test_plainCSVIsNotTreatedAsZip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).csv")
        try "Name,Year,Letterboxd URI\nHer,2013,https://boxd.it/h\n".write(to: url, atomically: true, encoding: .utf8)
        let files = try FileImporters.ImportFile.load(from: url)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try FileImporters.letterboxd(files).map(\.item.name), ["Her"])
    }
}

final class IMDbImportTests: XCTestCase {

    let ratingsExport = """
    Const,Your Rating,Date Rated,Title,Original Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors
    tt1375666,9,2023-05-01,Inception,Inception,https://www.imdb.com/title/tt1375666/,Movie,8.8,148,2010,"Action, Sci-Fi",2500000,2010-07-16,Christopher Nolan
    tt0903747,10,2023-05-02,Breaking Bad,Breaking Bad,https://www.imdb.com/title/tt0903747/,TV Series,9.5,49,2008,Drama,2000000,2008-01-20,
    tt6751668,7,2023-05-03,Parasite,Gisaengchung,https://www.imdb.com/title/tt6751668/,Movie,8.5,132,2019,Thriller,900000,2019-05-30,Bong Joon Ho
    tt0118799,3,2023-05-04,Some Short,Some Short,https://www.imdb.com/title/tt0118799/,Short,6.0,10,1997,Short,100,1997-01-01,Someone
    """

    func test_ratingsExport_keepsFilmsAndMapsTenPointRatings() throws {
        let files = [FileImporters.ImportFile(name: "ratings.csv", text: ratingsExport)]
        XCTAssertEqual(FileImporters.detect(files), .imdb)
        let items = try FileImporters.imdb(files).map(\.item)
        XCTAssertEqual(items.map(\.name), ["Inception", "Parasite", "Some Short"], "series skipped, highest rated first")
        XCTAssertEqual(items[0].imdbID, "tt1375666")
        XCTAssertEqual(items[0].suggestedBucket, .loved)
        XCTAssertEqual(items[0].sourceNote, "Rated 9/10 on IMDb")
        XCTAssertEqual(items[0].fallbackYear, 2010)
        XCTAssertEqual(items[1].suggestedBucket, .liked)
        XCTAssertEqual(items[2].suggestedBucket, .didntLike)
    }

    func test_watchlistExportWithoutRatings() throws {
        let csv = """
        Position,Const,Created,Modified,Description,Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors,Your Rating,Date Rated
        1,tt0111161,2023-01-01,2023-01-01,,The Shawshank Redemption,https://www.imdb.com/title/tt0111161/,Movie,9.3,142,1994,Drama,2900000,1994-10-14,Frank Darabont,,
        """
        let items = try FileImporters.imdb(csv).map(\.item)
        XCTAssertEqual(items.map(\.imdbID), ["tt0111161"])
        XCTAssertNil(items[0].suggestedBucket)
    }

    func test_exportDatesKeepTheirCalendarDay() throws {
        let date = try XCTUnwrap(FileImporters.parseDate("2024-03-02"))
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day], [2024, 3, 2])
    }

    func test_tenPointBuckets() {
        XCTAssertEqual(FileImporters.bucket(forTenPoint: 10), .loved)
        XCTAssertEqual(FileImporters.bucket(forTenPoint: 9), .loved)
        XCTAssertEqual(FileImporters.bucket(forTenPoint: 8), .liked)
        XCTAssertEqual(FileImporters.bucket(forTenPoint: 6), .fine)
        XCTAssertEqual(FileImporters.bucket(forTenPoint: 4), .didntLike)
    }

    @MainActor
    func test_imdbIDMatchesExistingMovieRegardlessOfTitle() {
        let list = RankList(name: "Films", category: .movies)
        let existing = RankItem(name: "Gisaengchung", bucket: .loved)
        existing.imdbURLString = "https://www.imdb.com/title/tt6751668/"
        existing.list = list
        list.items.append(existing)
        var staged = StagedItem(name: "Parasite", category: .movies)
        staged.imdbID = "tt6751668"
        XCTAssertTrue(ImportMatcher.list(list, contains: staged))
    }

    @MainActor
    func test_applyWritesIMDbLinkWithoutCatalogRecord() {
        var staged = StagedItem(name: "Inception", category: .movies)
        staged.imdbID = "tt1375666"
        staged.fallbackYear = 2010
        let item = RankItem(name: "", bucket: .loved)
        staged.apply(to: item)
        XCTAssertEqual(item.imdbURLString, "https://www.imdb.com/title/tt1375666/")
        XCTAssertEqual(item.releaseYear, 2010)
    }

    func test_enrichmentUsesExactIMDbLookup() async {
        struct StubMovies: MovieSearchService {
            func search(query: String) async throws -> [MovieSearchResult] {
                XCTFail("should not fall back to a title search"); return []
            }
            func lookup(imdbID: String) async throws -> MovieSearchResult? {
                MovieSearchResult(id: 27205, title: "Inception", releaseYear: 2010,
                                  posterURL: URL(string: "https://image.tmdb.org/p.jpg"),
                                  imdbURL: URL(string: "https://www.imdb.com/title/\(imdbID)/"))
            }
        }
        let enricher = ImportEnricher(movies: StubMovies(), books: MockBookSearchService(), anime: MockAnimeSearchService(),
                                      games: MockGameSearchService(), music: MockMusicSearchService())
        var staged = StagedItem(name: "Inception", category: .movies)
        staged.imdbID = "tt1375666"
        let enriched = await enricher.enrich(staged)
        XCTAssertEqual(enriched?.movie?.id, 27205)
        XCTAssertEqual(enriched?.artworkURLString, "https://image.tmdb.org/p.jpg")
    }
}

final class FileDetectionTests: XCTestCase {

    func test_detectsEachService() {
        func detect(_ header: String) -> ImportSourceKind? {
            FileImporters.detect([FileImporters.ImportFile(name: "x.csv", text: header + "\n")])
        }
        XCTAssertEqual(detect("Date,Name,Year,Letterboxd URI"), .letterboxd)
        XCTAssertEqual(detect("Book Id,Title,Author,Exclusive Shelf"), .goodreads)
        XCTAssertEqual(detect("\u{FEFF}Title,Authors,ISBN/UID,Read Status,Star Rating"), .storyGraph)
        XCTAssertEqual(detect("Const,Your Rating,Date Rated,Title"), .imdb)
        XCTAssertNil(detect("foo,bar"))
    }
}

final class SteamSignInTests: XCTestCase {

    func test_loginURLRequestsIdentifierSelect() throws {
        let items = try XCTUnwrap(URLComponents(url: SteamSignIn.loginURL, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "openid.return_to" }?.value, "anyrank://steam-auth")
        XCTAssertEqual(items.first { $0.name == "openid.mode" }?.value, "checkid_setup")
    }

    func test_parsesSteamIDFromCallback() {
        let ok = URL(string: "anyrank://steam-auth?openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0&openid.mode=id_res&openid.claimed_id=https%3A%2F%2Fsteamcommunity.com%2Fopenid%2Fid%2F76561197960287930")!
        XCTAssertEqual(SteamSignIn.steamID(fromCallback: ok), "76561197960287930")
        let cancelled = URL(string: "anyrank://steam-auth?openid.mode=cancel")!
        XCTAssertNil(SteamSignIn.steamID(fromCallback: cancelled))
    }
}
