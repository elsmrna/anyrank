import Foundation

/// Parsers for services' own CSV exports, plus the plain pasted list. Each
/// turns a document into ordered import candidates. They carry the source's
/// rating as a *suggested* bucket and a note — the user still places every
/// item through the comparison flow.
enum FileImporters {

    enum ParseError: LocalizedError {
        case unrecognized(expected: String)
        case wrongCategory(source: ImportSourceKind, listCategory: Category)
        case empty

        var errorDescription: String? {
            switch self {
            case .unrecognized(let expected):
                return "This file doesn't look like \(expected). Check you picked the right export."
            case .wrongCategory(let source, let listCategory):
                return "That's a \(source.displayName) export, which imports \(source.category?.displayName.lowercased() ?? "items") — this list is for \(listCategory.displayName.lowercased())."
            case .empty:
                return "Nothing to import in this file."
            }
        }
    }

    /// One CSV document, from a picked file or from inside a picked .zip.
    struct ImportFile {
        let name: String
        let text: String

        /// Read a picked file. A .zip is opened and its CSVs returned, so
        /// users never have to unzip an export themselves.
        static func load(from url: URL) throws -> [ImportFile] {
            let data = try Data(contentsOf: url)
            if ZipReader.isZip(data) {
                let files = try ZipReader.entries(in: data)
                    .filter { $0.path.lowercased().hasSuffix(".csv") && !$0.path.hasPrefix("__MACOSX") }
                    .map { ImportFile(name: $0.path, text: String(decoding: $0.data, as: UTF8.self)) }
                guard !files.isEmpty else { throw ParseError.empty }
                return files
            }
            return [ImportFile(name: url.lastPathComponent, text: String(decoding: data, as: UTF8.self))]
        }
    }

    static func candidates(from text: String, source: ImportSourceKind, category: Category) throws -> [ImportCandidate] {
        try candidates(from: [ImportFile(name: "", text: text)], source: source, category: category)
    }

    static func candidates(from files: [ImportFile], source: ImportSourceKind, category: Category) throws -> [ImportCandidate] {
        switch source {
        case .letterboxd: return try letterboxd(files)
        case .imdb:       return try imdb(files)
        case .goodreads:  return try goodreads(files.map(\.text).joined(separator: "\n"))
        case .storyGraph: return try storyGraph(files.map(\.text).joined(separator: "\n"))
        case .pastedList: return pastedList(files.map(\.text).joined(separator: "\n"), category: category)
        case .steam:      return []
        }
    }

    /// Which service an export came from, judged by its column headers —
    /// so picking the "wrong" source on the previous screen still works.
    static func detect(_ files: [ImportFile]) -> ImportSourceKind? {
        for file in files {
            guard let header = try? CSV.decode(String(file.text.prefix(4_000))).first else { continue }
            let columns = Set(header.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{FEFF}", with: "") })
            if columns.contains("Letterboxd URI") { return .letterboxd }
            if columns.contains("Exclusive Shelf") { return .goodreads }
            if columns.contains("Read Status") { return .storyGraph }
            if columns.contains("Const") && (columns.contains("Title Type") || columns.contains("Your Rating")) { return .imdb }
        }
        return nil
    }

    // MARK: Letterboxd

    /// Letterboxd's data export (letterboxd.com/settings/data → Export your
    /// data) — the whole .zip, or any one of its CSVs. Files are merged per
    /// film (title + year): the current rating from ratings.csv, film links
    /// from watched/ratings, watch dates from diary.csv, reviews from
    /// reviews.csv. The watchlist is skipped — those films aren't watched.
    static func letterboxd(_ text: String) throws -> [ImportCandidate] {
        try letterboxd([ImportFile(name: "", text: text)])
    }

    static func letterboxd(_ files: [ImportFile]) throws -> [ImportCandidate] {
        struct Film {
            var name: String
            var year: Int?
            var filmURI: String?
            var entryURI: String?
            var currentRating: Double?
            var diaryRating: Double?
            var watched: Date?
            var review: String?
        }
        enum Kind { case watched, ratings, diary, reviews }

        let skipped = ["watchlist", "likes", "lists/", "deleted", "orphaned", "profile", "comments"]
        var films: [String: Film] = [:]
        var order: [String] = []
        var sawLetterboxdFile = false

        for file in files {
            let lower = file.name.lowercased()
            if skipped.contains(where: lower.contains) { continue }
            guard let table = try? Table(file.text, requiring: ["Name", "Letterboxd URI"], expected: "a Letterboxd export") else { continue }
            sawLetterboxdFile = true

            let kind: Kind
            if lower.hasSuffix("reviews.csv") || table.has("Review") { kind = .reviews }
            else if lower.hasSuffix("diary.csv") || table.has("Watched Date") { kind = .diary }
            else if lower.hasSuffix("ratings.csv") || table.has("Rating") { kind = .ratings }
            else { kind = .watched }

            for row in table.rows {
                guard let name = row["Name"] else { continue }
                let year = row["Year"].flatMap { Int($0) }
                let key = ImportMatcher.normalize(name) + "|" + (year.map(String.init) ?? "")
                var film = films[key] ?? Film(name: name, year: year)
                if films[key] == nil { order.append(key) }

                let uri = row["Letterboxd URI"]
                let rating = row["Rating"].flatMap(Double.init)
                let date = parseDate(row["Watched Date"] ?? row["Date"])
                switch kind {
                case .watched:
                    film.filmURI = film.filmURI ?? uri
                case .ratings:
                    film.filmURI = film.filmURI ?? uri
                    film.currentRating = rating ?? film.currentRating
                case .diary, .reviews:
                    // Diary/review links point at the entry, not the film.
                    film.entryURI = film.entryURI ?? uri
                    if let rating { film.diaryRating = Swift.max(film.diaryRating ?? 0, rating) }
                    if kind == .reviews, let review = row["Review"] { film.review = review }
                }
                film.watched = latest(film.watched, date)
                films[key] = film
            }
        }
        guard sawLetterboxdFile else { throw ParseError.unrecognized(expected: "a Letterboxd export") }

        let candidates: [ImportCandidate] = order.compactMap { key in
            guard let film = films[key] else { return nil }
            var staged = StagedItem(name: film.name, category: .movies)
            staged.fallbackYear = film.year
            staged.sourceURL = (film.filmURI ?? film.entryURI).flatMap(URL.init(string:))
            staged.dateConsumed = film.watched
            staged.notes = film.review
            if let rating = film.currentRating ?? film.diaryRating, rating > 0 {
                staged.suggestedBucket = bucket(forFiveStar: rating)
                staged.sourceNote = "Rated \(stars(rating)) on Letterboxd"
            }
            return ImportCandidate(item: staged)
        }
        return try nonEmpty(sortedByRatingThenDate(candidates))
    }

    // MARK: IMDb

    /// IMDb's ratings export, or any exported list or watchlist (same
    /// columns). Only film-like titles are kept — series, episodes, games
    /// and podcasts are skipped. Each row carries its IMDb ID, so posters
    /// come from an exact TMDB lookup rather than a title search.
    static func imdb(_ text: String) throws -> [ImportCandidate] {
        try imdb([ImportFile(name: "", text: text)])
    }

    static func imdb(_ files: [ImportFile]) throws -> [ImportCandidate] {
        let filmTypes: Set<String> = [
            "movie", "tv movie", "tvmovie", "short", "tv short", "tvshort",
            "video", "tv special", "tvspecial",
        ]
        var seen = Set<String>()
        var candidates: [ImportCandidate] = []
        var sawIMDbFile = false

        for file in files {
            guard let table = try? Table(file.text, requiring: ["Const", "Title"], expected: "an IMDb export") else { continue }
            sawIMDbFile = true
            for row in table.rows {
                guard let title = row["Title"],
                      let id = row["Const"].flatMap(ImportMatcher.Identity.imdbID(in:)),
                      seen.insert(id).inserted else { continue }
                if let type = row["Title Type"]?.lowercased(), !filmTypes.contains(type) { continue }

                var staged = StagedItem(name: title, category: .movies)
                staged.imdbID = id
                staged.fallbackYear = row["Year"].flatMap { Int($0) }
                staged.sourceURL = URL(string: "https://www.imdb.com/title/\(id)/")
                staged.dateConsumed = parseDate(row["Date Rated"])
                if let rating = row["Your Rating"].flatMap(Int.init), rating > 0 {
                    staged.suggestedBucket = bucket(forTenPoint: rating)
                    staged.sourceNote = "Rated \(rating)/10 on IMDb"
                }
                candidates.append(ImportCandidate(item: staged))
            }
        }
        guard sawIMDbFile else { throw ParseError.unrecognized(expected: "an IMDb export") }
        return try nonEmpty(sortedByRatingThenDate(candidates))
    }

    // MARK: Goodreads

    /// Goodreads' library export (My Books → Import and export). Only the
    /// "read" shelf is imported.
    static func goodreads(_ text: String) throws -> [ImportCandidate] {
        let table = try Table(text, requiring: ["Title", "Author", "Exclusive Shelf"], expected: "a Goodreads export")
        let candidates: [ImportCandidate] = table.rows.compactMap { row in
            guard row["Exclusive Shelf"] == "read", let title = row["Title"] else { return nil }
            let author = row["Author"] ?? ""
            let isbn = cleanISBN(row["ISBN13"]) ?? cleanISBN(row["ISBN"])
            let year = (row["Original Publication Year"] ?? row["Year Published"]).flatMap { Int($0) }
            var staged = StagedItem(name: title, category: .books)
            staged.book = BookSearchResult(
                id: row["Book Id"] ?? isbn ?? title,
                title: title,
                author: author,
                publicationYear: year,
                isbn: isbn,
                storyGraphURL: LiveBookSearchService.storyGraphURL(forTitle: title),
                coverURL: isbn.flatMap { URL(string: "https://covers.openlibrary.org/b/isbn/\($0)-M.jpg") }
            )
            staged.sourceURL = row["Book Id"].flatMap { URL(string: "https://www.goodreads.com/book/show/\($0)") }
            staged.dateConsumed = parseDate(row["Date Read"])
            staged.notes = row["My Review"]
            if let rating = row["My Rating"].flatMap(Double.init), rating > 0 {
                staged.suggestedBucket = bucket(forFiveStar: rating)
                staged.sourceNote = "Rated \(stars(rating)) on Goodreads"
            }
            return ImportCandidate(item: staged)
        }
        return try nonEmpty(sortedByRatingThenDate(candidates))
    }

    // MARK: StoryGraph

    /// StoryGraph's export (Manage Account → Export StoryGraph Library).
    /// Only books with Read Status "read" are imported.
    static func storyGraph(_ text: String) throws -> [ImportCandidate] {
        let table = try Table(text, requiring: ["Title", "Read Status"], expected: "a StoryGraph export")
        let candidates: [ImportCandidate] = table.rows.compactMap { row in
            guard row["Read Status"]?.lowercased() == "read", let title = row["Title"] else { return nil }
            let author = row["Authors"] ?? row["Author"] ?? ""
            let isbn = cleanISBN(row["ISBN/UID"])
            var staged = StagedItem(name: title, category: .books)
            staged.book = BookSearchResult(
                id: isbn ?? title,
                title: title,
                author: author,
                publicationYear: nil,
                isbn: isbn,
                storyGraphURL: LiveBookSearchService.storyGraphURL(forTitle: title),
                coverURL: isbn.flatMap { URL(string: "https://covers.openlibrary.org/b/isbn/\($0)-M.jpg") }
            )
            staged.dateConsumed = parseDate(row["Last Date Read"] ?? row["Date Added"])
            staged.notes = row["Review"]
            if let rating = row["Star Rating"].flatMap(Double.init), rating > 0 {
                staged.suggestedBucket = bucket(forFiveStar: rating)
                staged.sourceNote = "Rated \(stars(rating)) on StoryGraph"
            }
            return ImportCandidate(item: staged)
        }
        return try nonEmpty(sortedByRatingThenDate(candidates))
    }

    // MARK: Pasted list

    /// One item per line. Leading list markers ("1.", "-", "•") are removed;
    /// blank lines are ignored. Order is preserved.
    static func pastedList(_ text: String, category: Category) -> [ImportCandidate] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            var name = line.trimmingCharacters(in: .whitespaces)
            if let range = name.range(of: #"^(\d+[.)]|[-*•–])\s+"#, options: .regularExpression) {
                name.removeSubrange(range)
            }
            name = name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return ImportCandidate(item: StagedItem(name: name, category: category))
        }
    }

    // MARK: Helpers

    /// Ten-point scale (IMDb) → bucket.
    static func bucket(forTenPoint rating: Int) -> Bucket {
        switch rating {
        case 9...:  return .loved
        case 7...8: return .liked
        case 5...6: return .fine
        default:    return .didntLike
        }
    }

    /// Five-star scale → bucket. Half-stars round toward the nearer bucket.
    static func bucket(forFiveStar rating: Double) -> Bucket {
        switch rating {
        case 4.5...:   return .loved
        case 3.5..<4.5: return .liked
        case 2.5..<3.5: return .fine
        default:        return .didntLike
        }
    }

    static func stars(_ rating: Double) -> String {
        let whole = Int(rating)
        let half = rating - Double(whole) >= 0.5
        return String(repeating: "★", count: whole) + (half ? "½" : "")
    }

    /// Goodreads wraps ISBNs as `="9780…"`; empty ones as `=""`.
    static func cleanISBN(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let digits = raw.filter { $0.isNumber || $0 == "X" }
        return digits.count >= 10 ? digits : nil
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        for format in ["yyyy-MM-dd", "yyyy/MM/dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // Exports give calendar dates ("2024-03-02"), not instants. Read
            // them in the user's time zone so they display as the same day;
            // UTC midnight shows as the previous evening west of Greenwich.
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: String(raw.prefix(10))) { return date }
        }
        return nil
    }

    /// Rated items first (highest rating leading), then most recent.
    /// Ranking strong opinions first builds a useful skeleton quickly.
    private static func sortedByRatingThenDate(_ candidates: [ImportCandidate]) -> [ImportCandidate] {
        func weight(_ bucket: Bucket?) -> Int {
            switch bucket {
            case .loved: return 4
            case .liked: return 3
            case .fine: return 2
            case .didntLike: return 1
            case nil: return 0
            }
        }
        return candidates.enumerated().sorted { a, b in
            let wa = weight(a.element.item.suggestedBucket), wb = weight(b.element.item.suggestedBucket)
            if wa != wb { return wa > wb }
            let da = a.element.item.dateConsumed ?? .distantPast, db = b.element.item.dateConsumed ?? .distantPast
            if da != db { return da > db }
            return a.offset < b.offset
        }.map(\.element)
    }

    private static func nonEmpty(_ candidates: [ImportCandidate]) throws -> [ImportCandidate] {
        guard !candidates.isEmpty else { throw ParseError.empty }
        return candidates
    }

    // MARK: Header-keyed table

    /// A CSV document addressed by header name.
    struct Table {
        struct Row {
            let values: [String]
            let columns: [String: Int]

            /// Trimmed value, or nil when missing/empty.
            subscript(_ column: String) -> String? {
                guard let i = columns[column], i < values.count else { return nil }
                let value = values[i].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }

        let rows: [Row]
        private let columns: Set<String>

        func has(_ column: String) -> Bool { columns.contains(column) }

        init(_ text: String, requiring required: [String], expected: String) throws {
            // Strip a UTF-8 BOM, which some exports include.
            let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
            let parsed = try CSV.decode(cleaned)
            guard let header = parsed.first else { throw ParseError.empty }
            var columns: [String: Int] = [:]
            for (i, name) in header.enumerated() where columns[name.trimmingCharacters(in: .whitespaces)] == nil {
                columns[name.trimmingCharacters(in: .whitespaces)] = i
            }
            guard required.allSatisfy({ columns[$0] != nil }) else {
                throw ParseError.unrecognized(expected: expected)
            }
            self.columns = Set(columns.keys)
            rows = parsed.dropFirst().map { Row(values: $0, columns: columns) }
        }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private func latest(_ a: Date?, _ b: Date?) -> Date? {
    switch (a, b) {
    case let (a?, b?): return Swift.max(a, b)
    default: return a ?? b
    }
}
