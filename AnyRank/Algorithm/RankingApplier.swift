import Foundation

/// Applies a `RankingSession.Placement` to a `RankList` via the repository.
/// Pure algorithm code mutates lists/items directly; persistence is the
/// repository's job.
@MainActor
enum RankingApplier {

    /// Insert `item` into `list` according to `placement`, append the
    /// comparison records, and renormalize scores in the affected bucket(s).
    /// Use this for both initial placement and re-rank.
    ///
    /// For re-rank, callers should remove the item from the snapshot before
    /// computing the placement so it isn't compared against itself.
    static func apply(
        placement: RankingSession.Placement,
        item: RankItem,
        list: RankList,
        repository: Repository,
        comparisonKindOverride: ComparisonKind? = nil
    ) {
        // 1. Insert the item into the list if it's new, then update its bucket.
        if !list.items.contains(where: { $0.id == item.id }) {
            list.items.append(item)
            item.list = list
        }
        let newBucket = placement.bucket
        let previousBucket = item.bucket
        item.bucket = newBucket

        // 2. Renormalize the new bucket's ordering. We rebuild it manually
        // because score-sorted order before this call may not reflect the
        // post-insert ordering.
        var ordered = list.items(in: newBucket).filter { $0.id != item.id }
        let position = max(0, min(placement.rankInBucket, ordered.count))
        ordered.insert(item, at: position)
        ScoreInterpolation.renormalize(ordered, in: newBucket)

        // 3. If the item crossed buckets (boundary promote/demote, or
        // re-rank into a different bucket), renormalize the previous bucket too.
        if previousBucket != newBucket {
            let previousOrdered = list.items(in: previousBucket).filter { $0.id != item.id }
            ScoreInterpolation.renormalize(previousOrdered, in: previousBucket)
        }

        // 4. Append comparison records to the list. Repository persistence
        // happens in step 6.
        for proposed in placement.comparisons {
            let kind = comparisonKindOverride ?? proposed.kind
            let record = ComparisonRecord(
                winnerItemID: proposed.winnerItemID,
                loserItemID: proposed.loserItemID,
                kind: kind
            )
            list.comparisons.append(record)
        }

        // 5. Bump the periodic re-rank counter on initial adds only.
        if comparisonKindOverride != .rerank {
            list.additionsSinceLastRerankPrompt += 1
        }

        // 6. Persist the whole list (items CSV + comparisons CSV + index entry).
        repository.touch(list)
    }

    /// Remove an item from its list and renormalize the affected bucket.
    static func delete(
        item: RankItem,
        from list: RankList,
        repository: Repository
    ) {
        let bucket = item.bucket
        list.items.removeAll { $0.id == item.id }
        let remaining = list.items(in: bucket)
        ScoreInterpolation.renormalize(remaining, in: bucket)
        repository.touch(list)
    }

    /// Build a `RankingSession.ListSnapshot` from a `RankList`, optionally
    /// excluding a specific item (used during re-rank so the item being
    /// re-ranked isn't compared against itself).
    ///
    /// Populates ItemRef with the thumbnail URL and secondary text for
    /// the comparison card. Category-specific: poster for movies, cover
    /// for books, address for places, nothing for free-form custom items.
    static func snapshot(of list: RankList, excludingItemID excluded: UUID? = nil) -> RankingSession.ListSnapshot {
        var bucketContents: [Bucket: [RankingSession.ItemRef]] = [:]
        for bucket in Bucket.allCases {
            let refs = list.items(in: bucket)
                .filter { excluded == nil || $0.id != excluded }
                .map { item in
                    RankingSession.ItemRef(
                        id: item.id,
                        name: item.name,
                        imageURLString: comparisonImageURLString(for: item, in: list),
                        secondaryText: comparisonSecondaryText(for: item, in: list)
                    )
                }
            bucketContents[bucket] = refs
        }
        return .init(bucketContents: bucketContents)
    }

    /// Category-appropriate thumbnail URL for the comparison card. Places
    /// use a photo reference by place ID (see `PlacePhotos`).
    static func comparisonImageURLString(for item: RankItem, in list: RankList) -> String? {
        switch list.category {
        case .movies, .tv: return item.posterURLString
        case .books:  return item.coverURLString
        case .anime, .manga: return item.coverURLString
        case .games:  return item.coverURLString
        case .boardGames: return item.coverURLString
        case .bands: return item.coverURLString
        case .albums: return item.coverURLString
        case .restaurants, .bars, .stays: return PlacePhotos.url(forPlaceID: item.placeID)
        case .custom: return list.linksToMapsLocation ? PlacePhotos.url(forPlaceID: item.placeID) : nil
        }
    }

    /// Category-appropriate secondary text under the item name.
    /// Nil-safe: empty strings return nil so the card lays out cleanly.
    static func comparisonSecondaryText(for item: RankItem, in list: RankList) -> String? {
        switch list.category {
        case .movies:
            return item.releaseYear.map { String($0) }
        case .tv:
            return TVShowText.secondary(year: item.releaseYear, seasons: item.seasonCount)
        case .books:
            if let author = item.author, !author.isEmpty {
                if let year = item.releaseYear { return "\(author) · \(year)" }
                return author
            }
            return item.releaseYear.map { String($0) }
        case .anime:
            var parts: [String] = []
            if let year = item.releaseYear { parts.append(String(year)) }
            if let eps = item.episodeCount, eps > 1 { parts.append("\(eps) eps") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .manga:
            let parts = [item.releaseYear.map { String($0) }, MangaLength.text(chapters: item.chapterCount, volumes: item.volumeCount)]
                .compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .boardGames:
            return BoardGameText.secondary(year: item.releaseYear, minPlayers: item.minPlayers, maxPlayers: item.maxPlayers)
        case .bands:
            return ArtistText.fans(item.fanCount)
        case .games:
            var parts: [String] = []
            let platforms = item.platforms ?? []
            if !platforms.isEmpty {
                // Same 3-platform cap as the search screen, so the
                // comparison card doesn't wrap.
                let shown = platforms.prefix(3).joined(separator: ", ")
                let remaining = platforms.count - 3
                parts.append(remaining > 0 ? "\(shown) +\(remaining) more" : shown)
            }
            if let year = item.releaseYear { parts.append(String(year)) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .albums:
            if let artist = item.artist, !artist.isEmpty {
                if let year = item.releaseYear { return "\(artist) · \(year)" }
                return artist
            }
            return item.releaseYear.map { String($0) }
        case .restaurants, .bars, .stays:
            let addr = item.address ?? ""
            return addr.isEmpty ? nil : addr
        case .custom:
            let addr = item.address ?? ""
            return addr.isEmpty ? nil : addr
        }
    }
}
