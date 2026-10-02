import SwiftUI

/// Row for a single item in the list-detail view: rank, artwork (for
/// categories that have it), name, a secondary detail, and a bucket-tinted
/// score badge. The badge shows the bucket glyph until the bucket has
/// enough items for the score to mean something (Spec § 4).
struct ItemRow: View {
    let item: RankItem
    /// 1-based position in the whole list; nil hides the rank column.
    var rank: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)")
                    .font(.score(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(minWidth: 20, alignment: .trailing)
            }

            if let list = item.list, list.showsArtwork {
                ArtworkView(
                    urlString: RankingApplier.comparisonImageURLString(for: item, in: list),
                    category: list.category,
                    width: 36,
                    cornerRadius: 6
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let secondary = secondaryText, !secondary.isEmpty {
                    Text(secondary)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            ScoreBadge(bucket: item.bucket, score: item.shouldDisplayScore ? item.score : nil)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var secondaryText: String? {
        switch item.list?.category {
        case .restaurants, .bars, .stays: return item.address
        case .movies: return item.releaseYear.map { String($0) }
        case .books:
            // Author is the most useful disambiguator; year is appended
            // when present since multiple editions of the same title exist.
            if let author = item.author, let year = item.releaseYear {
                return "\(author) · \(year)"
            }
            return item.author ?? item.releaseYear.map { String($0) }
        case .anime:
            // Format + year is the disambiguator for anime — e.g. a
            // TV series and a film with the same franchise name.
            var parts: [String] = []
            if let fmt = item.animeFormat, !fmt.isEmpty { parts.append(fmt.capitalized) }
            if let year = item.releaseYear { parts.append(String(year)) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .manga:
            // Format matters more than for anime: manga vs. manhwa vs. a
            // light novel of the same series.
            let parts = [item.animeFormat, item.releaseYear.map { String($0) }].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .games:
            // Year is the most useful disambiguator across remasters.
            // Platforms fit better in the item detail than a row.
            return item.releaseYear.map { String($0) }
        case .albums:
            if let artist = item.artist, let year = item.releaseYear {
                return "\(artist) · \(year)"
            }
            return item.artist ?? item.releaseYear.map { String($0) }
        case .songs:
            if let artist = item.artist, let album = item.albumTitle {
                return "\(artist) · \(album)"
            }
            return item.artist
        case .custom, .none: return item.customLinkString
        }
    }
}

#Preview {
    let repo = PreviewSupport.fullRestaurantsRepository()
    let list = repo.lists.first!
    return List {
        ForEach(list.itemsSortedByScore()) { item in
            ItemRow(item: item, rank: 1)
        }
    }
}
