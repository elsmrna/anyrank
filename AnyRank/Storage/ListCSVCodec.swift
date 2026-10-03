import Foundation

/// Encode/decode a `RankList`'s items as CSV. The first row is the column
/// header. Per-list custom fields expand to `custom_<fieldName>` columns
/// preserving the order declared on `RankList.customFieldNames`.
///
/// The codec is symmetric: `encodeItems(of:)` followed by
/// `decodeItems(into:from:)` round-trips losslessly.
enum ListCSVCodec {

    // MARK: Items

    /// Canonical column order for predefined fields. Category-specific
    /// fields are written for every list regardless of category — empty
    /// strings when not applicable — so the spreadsheet has stable columns.
    /// Custom fields are appended after, in `customFieldNames` order.
    ///
    /// `@MainActor` because `list.customFieldNames` lives on the
    /// main-actor-isolated `RankList` model. All other methods on this
    /// enum that touch `RankList`/`RankItem` are already MainActor;
    /// this one was the outlier.
    @MainActor
    static func columnHeaders(for list: RankList) -> [String] {
        var headers = baseColumns
        for name in list.customFieldNames {
            headers.append("custom_\(name)")
        }
        return headers
    }

    private static let baseColumns: [String] = [
        "id", "name", "bucket", "score",
        "date_consumed", "notes",
        "place_id", "address", "latitude", "longitude", "maps_url",
        "tmdb_id", "release_year", "poster_url", "imdb_url", "season_count",
        "author", "isbn", "storygraph_url", "cover_url",
        "anime_format", "episode_count", "anilist_url",
        "chapter_count", "volume_count",
        "platforms", "igdb_url",
        "artist", "spotify_url",
        "custom_link",
        "source_url"
    ]

    @MainActor
    static func encodeItems(of list: RankList) -> String {
        var rows: [[String]] = []
        rows.append(columnHeaders(for: list))
        for item in list.itemsSortedByScore() {
            rows.append(row(for: item, customFieldNames: list.customFieldNames))
        }
        return CSV.encode(rows: rows)
    }

    @MainActor
    private static func row(for item: RankItem, customFieldNames: [String]) -> [String] {
        var values: [String] = [
            item.id.uuidString,
            item.name,
            item.bucket.rawValue,
            String(item.score),
            item.dateConsumed.map { Self.formatDate($0) } ?? "",
            item.notes,
            item.placeID ?? "",
            item.address ?? "",
            item.latitude.map { String($0) } ?? "",
            item.longitude.map { String($0) } ?? "",
            item.mapsURLString ?? "",
            item.tmdbID.map { String($0) } ?? "",
            item.releaseYear.map { String($0) } ?? "",
            item.posterURLString ?? "",
            item.imdbURLString ?? "",
            item.seasonCount.map { String($0) } ?? "",
            item.author ?? "",
            item.isbn ?? "",
            item.storyGraphURLString ?? "",
            item.coverURLString ?? "",
            item.animeFormat ?? "",
            item.episodeCount.map { String($0) } ?? "",
            item.aniListURLString ?? "",
            item.chapterCount.map { String($0) } ?? "",
            item.volumeCount.map { String($0) } ?? "",
            (item.platforms ?? []).joined(separator: "|"),
            item.igdbURLString ?? "",
            item.artist ?? "",
            item.spotifyURLString ?? "",
            item.customLinkString ?? "",
            item.sourceURLString ?? ""
        ]
        for name in customFieldNames {
            values.append(item.customFieldValues[name] ?? "")
        }
        return values
    }

    @MainActor
    static func decodeItems(into list: RankList, from text: String) throws {
        let rows = try CSV.decode(text)
        guard let header = rows.first else {
            list.items = []
            return
        }
        let payload = rows.dropFirst()
        let columnIndex = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        var newItems: [RankItem] = []
        for row in payload {
            guard let item = try decodeItemRow(row, columnIndex: columnIndex, list: list) else { continue }
            newItems.append(item)
        }
        list.items = newItems
    }

    @MainActor
    private static func decodeItemRow(
        _ row: [String],
        columnIndex: [String: Int],
        list: RankList
    ) throws -> RankItem? {
        guard let idString = field(row, columnIndex, "id"),
              let id = UUID(uuidString: idString) else {
            // Skip malformed rows rather than throwing — better to lose one
            // item than fail to open a list.
            return nil
        }
        let name = field(row, columnIndex, "name") ?? ""
        let bucketRaw = field(row, columnIndex, "bucket") ?? Bucket.fine.rawValue
        let bucket = Bucket(rawValue: bucketRaw) ?? .fine
        let score = field(row, columnIndex, "score").flatMap(Double.init) ?? 0.0

        let item = RankItem(
            id: id,
            name: name,
            bucket: bucket,
            score: score,
            notes: field(row, columnIndex, "notes") ?? "",
            dateConsumed: field(row, columnIndex, "date_consumed").flatMap { Self.parseDate($0) }
        )
        item.list = list

        item.placeID = field(row, columnIndex, "place_id")
        item.address = field(row, columnIndex, "address")
        item.latitude = field(row, columnIndex, "latitude").flatMap(Double.init)
        item.longitude = field(row, columnIndex, "longitude").flatMap(Double.init)
        item.mapsURLString = field(row, columnIndex, "maps_url")

        item.tmdbID = field(row, columnIndex, "tmdb_id").flatMap(Int.init)
        item.releaseYear = field(row, columnIndex, "release_year").flatMap(Int.init)
        item.posterURLString = field(row, columnIndex, "poster_url")
        item.imdbURLString = field(row, columnIndex, "imdb_url")
        item.seasonCount = field(row, columnIndex, "season_count").flatMap(Int.init)

        item.author = field(row, columnIndex, "author")
        item.isbn = field(row, columnIndex, "isbn")
        item.storyGraphURLString = field(row, columnIndex, "storygraph_url")
        item.coverURLString = field(row, columnIndex, "cover_url")

        item.animeFormat = field(row, columnIndex, "anime_format")
        item.episodeCount = field(row, columnIndex, "episode_count").flatMap(Int.init)
        item.aniListURLString = field(row, columnIndex, "anilist_url")
        item.chapterCount = field(row, columnIndex, "chapter_count").flatMap(Int.init)
        item.volumeCount = field(row, columnIndex, "volume_count").flatMap(Int.init)

        if let platformsRaw = field(row, columnIndex, "platforms"), !platformsRaw.isEmpty {
            item.platforms = platformsRaw.split(separator: "|").map(String.init)
        }
        item.igdbURLString = field(row, columnIndex, "igdb_url")

        item.artist = field(row, columnIndex, "artist")
        item.spotifyURLString = field(row, columnIndex, "spotify_url")

        item.customLinkString = field(row, columnIndex, "custom_link")
        item.sourceURLString = field(row, columnIndex, "source_url")

        for name in list.customFieldNames {
            if let value = field(row, columnIndex, "custom_\(name)"), !value.isEmpty {
                item.customFieldValues[name] = value
            }
        }

        return item
    }

    private static func field(_ row: [String], _ columnIndex: [String: Int], _ name: String) -> String? {
        guard let idx = columnIndex[name], idx < row.count else { return nil }
        let v = row[idx]
        return v.isEmpty ? nil : v
    }

    // MARK: Comparisons

    static let comparisonHeaders: [String] = [
        "id", "timestamp", "winner_item_id", "loser_item_id", "kind"
    ]

    @MainActor
    static func encodeComparisons(of list: RankList) -> String {
        var rows: [[String]] = [comparisonHeaders]
        let sorted = list.comparisons.sorted { $0.timestamp < $1.timestamp }
        for record in sorted {
            rows.append([
                record.id.uuidString,
                Self.formatDate(record.timestamp),
                record.winnerItemID.uuidString,
                record.loserItemID.uuidString,
                record.kind.rawValue
            ])
        }
        return CSV.encode(rows: rows)
    }

    @MainActor
    static func decodeComparisons(into list: RankList, from text: String) throws {
        let rows = try CSV.decode(text)
        guard let header = rows.first else {
            list.comparisons = []
            return
        }
        let payload = rows.dropFirst()
        let columnIndex = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        var records: [ComparisonRecord] = []
        for row in payload {
            guard let idStr = field(row, columnIndex, "id"),
                  let id = UUID(uuidString: idStr),
                  let winnerStr = field(row, columnIndex, "winner_item_id"),
                  let winner = UUID(uuidString: winnerStr),
                  let loserStr = field(row, columnIndex, "loser_item_id"),
                  let loser = UUID(uuidString: loserStr) else { continue }

            let kind = (field(row, columnIndex, "kind").flatMap(ComparisonKind.init)) ?? .binarySearch
            let timestamp = field(row, columnIndex, "timestamp").flatMap { Self.parseDate($0) } ?? Date()

            records.append(.init(
                id: id,
                winnerItemID: winner,
                loserItemID: loser,
                kind: kind,
                timestamp: timestamp
            ))
        }
        list.comparisons = records
    }

    // MARK: Date helpers

    /// ISO 8601 with fractional seconds — round-trip stable through Google Sheets
    /// and Excel, parseable by Python pandas, JavaScript Date, etc.
    ///
    /// `nonisolated(unsafe)` because `ISO8601DateFormatter` isn't marked
    /// `Sendable` even though Apple documents its read-only methods as
    /// thread-safe. We initialize once at file scope and only ever call
    /// `string(from:)` / `date(from:)`, both of which are safe on shared
    /// instances per Foundation's guarantees.
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func formatDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func parseDate(_ string: String) -> Date? {
        if let d = isoFormatter.date(from: string) { return d }
        // Fallback: tolerant ISO 8601 without fractional seconds.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}
