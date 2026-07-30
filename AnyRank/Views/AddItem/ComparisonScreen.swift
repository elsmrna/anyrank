import SwiftUI

/// Phase 3 of add-item: side-by-side comparison. Shown when the
/// `RankingSession` is in `.askingComparison`. Vertical stack layout —
/// new item on top, opponent below — chosen so the lower card sits in
/// the thumb zone for one-handed use.
///
/// Cards carry a thumbnail (movie poster, book cover, or a category
/// placeholder), the name, and a one-line supporting text (year, author,
/// address). The whole card is the tap target — big, obvious, safe for
/// quick decisions.
///
/// A round label at the top ("Comparison 2 of ~3") keeps the user
/// oriented — an earlier version showed only the current round, which
/// made users feel like each new question came out of nowhere.
struct ComparisonScreen: View {
    let newItemName: String
    /// Optional thumbnail URL for the new (staged) item — poster / cover.
    let newItemImageURLString: String?
    /// Optional one-line supporting text for the new item.
    let newItemSecondaryText: String?
    let session: RankingSession
    let onAnswer: (UUID) -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Round + estimated total. Small pill, sentence case, low
            // contrast — signal not spectacle.
            Text(roundLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.top, 16)

            Text("Which did you prefer?")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 4)

            if let opponent = currentOpponent {
                VStack(spacing: 10) {
                    ComparisonCard(
                        name: newItemName,
                        secondary: newItemSecondaryText,
                        imageURLString: newItemImageURLString,
                        isNew: true
                    ) {
                        onAnswer(session.newItemID)
                    }

                    Text("vs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(1)

                    ComparisonCard(
                        name: opponent.name,
                        secondary: opponent.secondaryText,
                        imageURLString: opponent.imageURLString,
                        isNew: false
                    ) {
                        onAnswer(opponent.id)
                    }
                }
                .padding(.horizontal, 16)
                // Key the whole stack by the opponent so a new round is a
                // distinct view identity — cards fade+slide in rather
                // than silently swapping text.
                .id(opponent.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .animation(.easeInOut(duration: 0.22), value: opponent.id)

                if let kindLabel {
                    Text(kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            } else {
                ProgressView()
            }

            Spacer()
        }
    }

    private var currentOpponent: RankingSession.ItemRef? {
        if case .askingComparison(let against, _) = session.state { return against }
        return nil
    }

    private var kindLabel: String? {
        guard case .askingComparison(_, let kind) = session.state else { return nil }
        switch kind {
        case .binarySearch: return nil
        case .boundaryCheck: return "Checking the bucket boundary"
        case .tieBreak: return "Breaking a tie"
        case .rerank: return nil
        }
    }

    /// Human-readable progress marker. During binary search it's a "N of
    /// ~M" estimate; during tie-break / boundary check we swap the labels
    /// so the user knows this is a different sort of question.
    private var roundLabel: String {
        switch session.state {
        case .askingComparison(_, .binarySearch):
            let n = max(session.binarySearchComparisonsUsed, 1)
            let m = session.estimatedTotalRounds
            return "Comparison \(n) of ~\(m)"
        case .askingComparison(_, .tieBreak):
            return "Tie-break"
        case .askingComparison(_, .boundaryCheck):
            return "Bucket boundary check"
        default:
            return "Comparison"
        }
    }
}

// MARK: - Card

private struct ComparisonCard: View {
    let name: String
    let secondary: String?
    let imageURLString: String?
    let isNew: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    if isNew {
                        Text("NEW")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundColor(.white)
                    }
                    Text(name)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    if let secondary, !secondary.isEmpty {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor.opacity(isNew ? 0.5 : 0.0), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    /// 56×80 thumbnail — poster/cover aspect ratio when we have art,
    /// or a category-neutral placeholder square. AsyncImage handles
    /// loading + failure without extra state; when there's no URL, the
    /// placeholder view runs directly.
    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let urlString = imageURLString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty:
                        placeholder
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 56, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemBackground)
            Image(systemName: "square.on.square.dashed")
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Previews

#Preview("Movies — with posters") {
    let snapshot = RankingSession.ListSnapshot(bucketContents: [
        .loved: [
            .init(
                id: UUID(),
                name: "The Dark Knight",
                imageURLString: nil,
                secondaryText: "2008"
            ),
            .init(
                id: UUID(),
                name: "Pulp Fiction",
                imageURLString: nil,
                secondaryText: "1994"
            )
        ]
    ])
    let session = RankingSession(snapshot: snapshot, newItemID: UUID())
    session.selectBucket(.loved)
    return ComparisonScreen(
        newItemName: "Poor Things",
        newItemImageURLString: nil,
        newItemSecondaryText: "2023",
        session: session,
        onAnswer: { _ in }
    )
}

#Preview("Restaurants — no images") {
    let snapshot = RankingSession.ListSnapshot(bucketContents: [
        .loved: [
            .init(
                id: UUID(),
                name: "Bestia",
                imageURLString: nil,
                secondaryText: "2121 E 7th Pl, Los Angeles, CA"
            ),
            .init(
                id: UUID(),
                name: "Republique",
                imageURLString: nil,
                secondaryText: "624 S La Brea Ave, Los Angeles, CA"
            )
        ]
    ])
    let session = RankingSession(snapshot: snapshot, newItemID: UUID())
    session.selectBucket(.loved)
    return ComparisonScreen(
        newItemName: "Sushi Note",
        newItemImageURLString: nil,
        newItemSecondaryText: "13447 Ventura Blvd, Sherman Oaks, CA",
        session: session,
        onAnswer: { _ in }
    )
}
