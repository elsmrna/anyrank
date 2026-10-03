import Foundation

/// One entry produced by a source, before it's matched against a list.
struct ImportCandidate {
    var item: StagedItem
    /// The user never really engaged with this (a Steam game with zero
    /// playtime). Such items can be skipped wholesale at preview time.
    var neverEngaged: Bool = false
}

/// What an import will do, shown on the preview screen before committing.
struct ImportPlan {
    /// Items that will be queued for ranking, in order.
    let toRank: [StagedItem]
    let found: Int
    let alreadyInList: Int
    let alreadyQueued: Int
    let repeatedInSource: Int
    let skippedNeverEngaged: Int
}

/// Decides when two things are "the same item", so an import never queues
/// something the list already has (or has queued), and never queues the
/// same thing twice.
///
/// Strong identifiers (source URL, TMDB ID, ISBN, Maps place ID, Spotify
/// link…) match outright. Otherwise names are compared after normalizing
/// case, accents, ™/®, "&"/"and", and a leading "The" — with years required
/// to be compatible, so "Dune" (1984) and "Dune" (2021) stay distinct, and
/// addresses required to agree for places.
enum ImportMatcher {

    // MARK: Planning

    @MainActor
    static func plan(
        candidates: [ImportCandidate],
        target: RankList?,
        alreadyQueued: [StagedItem],
        skipNeverEngaged: Bool
    ) -> ImportPlan {
        var index = Index()
        target?.items.forEach { index.insert(Identity(item: $0, category: target!.category)) }

        var queuedIndex = Index()
        alreadyQueued.forEach { queuedIndex.insert(Identity(staged: $0)) }

        var toRank: [StagedItem] = []
        var seen = Index()
        var inList = 0, queued = 0, repeated = 0, neverEngaged = 0

        for candidate in candidates {
            let identity = Identity(staged: candidate.item)
            if index.contains(identity) { inList += 1; continue }
            if queuedIndex.contains(identity) { queued += 1; continue }
            if seen.contains(identity) { repeated += 1; continue }
            seen.insert(identity)
            if skipNeverEngaged && candidate.neverEngaged { neverEngaged += 1; continue }
            toRank.append(candidate.item)
        }

        return ImportPlan(
            toRank: toRank,
            found: candidates.count,
            alreadyInList: inList,
            alreadyQueued: queued,
            repeatedInSource: repeated,
            skippedNeverEngaged: neverEngaged
        )
    }

    /// `items` minus anything matching `existing` (or repeated within itself).
    static func removingMatches(_ items: [StagedItem], against existing: [StagedItem]) -> [StagedItem] {
        var index = Index()
        existing.forEach { index.insert(Identity(staged: $0)) }
        return items.filter { item in
            let identity = Identity(staged: item)
            guard !index.contains(identity) else { return false }
            index.insert(identity)
            return true
        }
    }

    /// Whether `staged` is already in `list`.
    @MainActor
    static func list(_ list: RankList, contains staged: StagedItem) -> Bool {
        let identity = Identity(staged: staged)
        return list.items.contains { Identity(item: $0, category: list.category).matches(identity) }
    }

    // MARK: Normalization

    static func normalize(_ name: String) -> String {
        var s = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        s = s.replacingOccurrences(of: "&", with: " and ")
        let kept = s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let words = String(kept).split(separator: " ")
        let trimmed = words.first == "the" && words.count > 1 ? words.dropFirst() : words[...]
        return trimmed.joined(separator: " ")
    }

    // MARK: Identity

    struct Identity {
        var strongKeys: Set<String> = []
        var name: String
        var year: Int?
        /// Extra key that must agree when both sides have it (place address).
        var qualifier: String?

        init(staged: StagedItem) {
            name = ImportMatcher.normalize(staged.name)
            if let url = staged.sourceURL { strongKeys.insert("src:\(url.absoluteString)") }
            if let imdb = staged.imdbID ?? staged.movie?.imdbURL.flatMap({ Self.imdbID(in: $0.absoluteString) }) {
                strongKeys.insert("imdb:\(imdb)")
            }
            if let place = staged.place {
                strongKeys.insert("place:\(place.id)")
                qualifier = ImportMatcher.normalize(place.address)
            }
            if let movie = staged.movie {
                if movie.id > 0 { strongKeys.insert("tmdb:\(movie.id)") }
                year = movie.releaseYear
            }
            if let tv = staged.tv {
                if tv.id > 0 { strongKeys.insert("tmdbtv:\(tv.id)") }
                year = tv.firstAirYear
            }
            if let book = staged.book {
                if let isbn = book.isbn.flatMap(Self.isbnKey) { strongKeys.insert(isbn) }
                year = book.publicationYear
            }
            if let anime = staged.anime { year = anime.seasonYear }
            if let manga = staged.manga { year = manga.startYear }
            if let game = staged.game { year = game.firstReleaseYear }
            if let album = staged.album {
                if let url = album.spotifyURL { strongKeys.insert("spotify:\(url.absoluteString)") }
                year = album.releaseYear
            }
            if year == nil { year = staged.fallbackYear }
        }

        @MainActor
        init(item: RankItem, category: Category) {
            name = ImportMatcher.normalize(item.name)
            year = item.releaseYear
            if let url = item.sourceURLString { strongKeys.insert("src:\(url)") }
            if let placeID = item.placeID { strongKeys.insert("place:\(placeID)") }
            if let address = item.address { qualifier = ImportMatcher.normalize(address) }
            if let tmdb = item.tmdbID, tmdb > 0 { strongKeys.insert("tmdb:\(tmdb)") }
            if let imdb = item.imdbURLString.flatMap(Self.imdbID(in:)) { strongKeys.insert("imdb:\(imdb)") }
            if let isbn = item.isbn.flatMap(Self.isbnKey) { strongKeys.insert(isbn) }
            if let url = item.spotifyURLString { strongKeys.insert("spotify:\(url)") }
        }

        func matches(_ other: Identity) -> Bool {
            if !strongKeys.isDisjoint(with: other.strongKeys) { return true }
            guard !name.isEmpty, name == other.name else { return false }
            if let a = year, let b = other.year, abs(a - b) > 1 { return false }
            if let a = qualifier, let b = other.qualifier, !a.isEmpty, !b.isEmpty, a != b { return false }
            return true
        }

        /// `tt1375666` from an IMDb URL or bare ID.
        static func imdbID(in text: String) -> String? {
            guard let range = text.range(of: #"tt\d{6,}"#, options: .regularExpression) else { return nil }
            return String(text[range])
        }

        private static func isbnKey(_ raw: String) -> String? {
            let digits = raw.filter { $0.isNumber || $0 == "X" || $0 == "x" }
            return digits.count >= 10 ? "isbn:\(digits.uppercased())" : nil
        }
    }

    /// Identities bucketed by normalized name so lookups stay fast for
    /// thousand-item libraries; strong keys are checked across the board.
    struct Index {
        private var byName: [String: [Identity]] = [:]
        private var strongKeys: Set<String> = []

        mutating func insert(_ identity: Identity) {
            byName[identity.name, default: []].append(identity)
            strongKeys.formUnion(identity.strongKeys)
        }

        func contains(_ identity: Identity) -> Bool {
            if !strongKeys.isDisjoint(with: identity.strongKeys) { return true }
            return byName[identity.name]?.contains { $0.matches(identity) } ?? false
        }
    }
}
