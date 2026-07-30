import SwiftUI

/// Row for a single item in the list-detail view. Shows the bucket accent,
/// the name, an optional score, an optional secondary detail, and a chevron
/// indicating tap-through.
struct ItemRow: View {
    let item: RankItem

    var body: some View {
        HStack(spacing: 12) {
            BucketAccent(bucket: item.bucket)
                .frame(height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                if let secondary = secondaryText {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if item.shouldDisplayScore {
                Text(formattedScore)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var formattedScore: String {
        String(format: "%.1f", item.score)
    }

    private var secondaryText: String? {
        switch item.list?.category {
        case .restaurants, .bars: return item.address
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
            ItemRow(item: item)
        }
    }
}
