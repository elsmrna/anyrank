import Foundation

/// Parsers for services' own CSV exports, plus the plain pasted list. Each
/// turns a document into ordered import candidates. They carry the source's
/// rating as a *suggested* bucket and a note — the user still places every
/// item through the comparison flow.
enum FileImporters {

    enum ParseError: LocalizedError {
        case unrecognized(expected: String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unrecognized(let expected):
                return "This file doesn't look like \(expected). Check you picked the right export."
            case .empty:
                return "Nothing to import in this file."
            }
        }
    }

    static func candidates(from text: String, source: ImportSourceKind, category: Category) throws -> [ImportCandidate] {
        switch source {
        case .letterboxd: return try letterboxd(text)
        case .goodreads:  return try goodreads(text)
        case .storyGraph: return try storyGraph(text)
        case .pastedList: return pastedList(text, category: category)
        case .steam:      return []
        }
    }

    // MARK: Letterboxd

    /// Accepts `watched.csv`, `ratings.csv`, or `diary.csv` from Letterboxd's
    /// data export (Settings → Import & Export → Export your data).
    static func letterboxd(_ text: String) throws -> [ImportCandidate] {
        let table = try Table(text, requiring: ["Name", "Letterboxd URI"], expected: "a Letterboxd export")

        // Diary exports repeat films on rewatch; keep one row per film with
        // the best rating and latest watch.
        var byURI: [String: (row: Table.Row, rating: Double?, date: Date?)] = [:]
        var order: [String] = []
        for row in table.rows {
            guard let uri = row["Letterboxd URI"], row["Name"] != nil else { continue }
            let rating = row["Rating"].flatMap(Double.init)
            let date = parseDate(row["Watched Date"] ?? row["Date"])
            if let existing = byURI[uri] {
                byURI[uri] = (row, Swift.max(existing.rating ?? 0, rating ?? 0).nonZero, latest(existing.date, date))
            } else {
                byURI[uri] = (row, rating, date)
                order.append(uri)
            }
        }

        let candidates: [ImportCandidate] = order.compactMap { uri in
            guard let entry = byURI[uri], let name = entry.row["Name"] else { return nil }
            var staged = StagedItem(name: name, category: .movies)
            staged.fallbackYear = entry.row["Year"].flatMap { Int($0) }
            staged.sourceURL = URL(string: uri)
            staged.dateConsumed = entry.date
            staged.notes = entry.row["Review"]
            if let rating = entry.rating {
                staged.suggestedBucket = bucket(forFiveStar: rating)
                staged.sourceNote = "Rated \(stars(rating)) on Letterboxd"
            }
            return ImportCandidate(item: staged)
        }
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
            formatter.timeZone = TimeZone(identifier: "UTC")
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

        init(_ text: String, requiring required: [String], expected: String) throws {
            // Strip a UTF-8 BOM, which some exports include.
            let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
            let parsed = try CSV.decode(cleaned)
            guard let header = parsed.first else { throw ParseError.empty }
            var columns: [String: Int] = [:]
            for (i, name) in header.enumerated() {
                columns[name.trimmingCharacters(in: .whitespaces)] = i
            }
            guard required.allSatisfy({ columns[$0] != nil }) else {
                throw ParseError.unrecognized(expected: expected)
            }
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
