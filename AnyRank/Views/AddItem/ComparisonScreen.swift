import SwiftUI

/// Phase 3 of add-item: head-to-head comparison. Shown when the
/// `RankingSession` is in `.askingComparison`. Vertical stack — the new
/// item on top stays put while each opponent slides in below, in the
/// thumb zone for one-handed use. The whole card is the tap target.
///
/// A progress bar and "Round 2 of ~3" label keep the user oriented —
/// an earlier version showed only the current round, which made each
/// new question feel like it came out of nowhere.
struct ComparisonScreen: View {
    let newItemName: String
    /// Optional thumbnail URL for the new (staged) item — poster / cover.
    var newItemImageURLString: String? = nil
    /// Optional one-line supporting text for the new item.
    var newItemSecondaryText: String? = nil
    /// Drives the artwork placeholder and aspect ratio.
    var category: Category = .custom
    let session: RankingSession
    let onAnswer: (UUID) -> Void

    @State private var answers = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                progressHeader

                if let opponent = currentOpponent {
                    VStack(spacing: 0) {
                        ComparisonCard(
                            name: newItemName,
                            secondary: newItemSecondaryText,
                            imageURLString: newItemImageURLString,
                            category: category,
                            isNew: true
                        ) {
                            answer(session.newItemID)
                        }

                        versusDivider

                        ComparisonCard(
                            name: opponent.name,
                            secondary: opponent.secondaryText,
                            imageURLString: opponent.imageURLString,
                            category: category,
                            isNew: false
                        ) {
                            answer(opponent.id)
                        }
                        // Key by opponent so each round is a distinct view
                        // identity — the new rival slides in rather than
                        // the text silently swapping.
                        .id(opponent.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    }

                    if let kindLabel {
                        Label(kindLabel, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    ProgressView()
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .screenBackground()
        .sensoryFeedback(.impact(weight: .light), trigger: answers)
    }

    private func answer(_ winner: UUID) {
        answers += 1
        withAnimation(Theme.spring) {
            onAnswer(winner)
        }
    }

    // MARK: Header

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(roundLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            ProgressView(value: progress)
                .progressViewStyle(SlimProgressStyle())
            Text("Which did you prefer?")
                .font(.display(.title))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    private var versusDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Text("or")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        .accessibilityHidden(true)
    }

    private var currentOpponent: RankingSession.ItemRef? {
        if case .askingComparison(let against, _) = session.state { return against }
        return nil
    }

    private var kindLabel: String? {
        guard case .askingComparison(_, let kind) = session.state else { return nil }
        switch kind {
        case .binarySearch: return nil
        case .boundaryCheck: return "This one's from a neighboring bucket"
        case .tieBreak: return "One last tie-breaker"
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
            return "Round \(n) of ~\(m)"
        case .askingComparison(_, .tieBreak):
            return "Tie-breaker"
        case .askingComparison(_, .boundaryCheck):
            return "Final check"
        default:
            return "Comparing"
        }
    }

    private var progress: Double {
        let m = max(session.estimatedTotalRounds, 1)
        switch session.state {
        case .askingComparison(_, .binarySearch):
            let n = max(session.binarySearchComparisonsUsed, 1)
            return min(Double(n) / Double(m), 0.9)
        case .askingComparison:
            return 0.92
        default:
            return 0
        }
    }
}

private struct SlimProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(8, geo.size.width * (configuration.fractionCompleted ?? 0)))
            }
        }
        .frame(height: 5)
        .animation(Theme.spring, value: configuration.fractionCompleted)
    }
}

// MARK: - Card

private struct ComparisonCard: View {
    let name: String
    let secondary: String?
    let imageURLString: String?
    let category: Category
    let isNew: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ArtworkView(
                    urlString: imageURLString,
                    category: category,
                    width: category.artworkAspectRatio == 1 ? 80 : 64,
                    cornerRadius: 10
                )
                VStack(alignment: .leading, spacing: 6) {
                    if isNew {
                        Text("New")
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.14), in: Capsule())
                    }
                    Text(name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let secondary, !secondary.isEmpty {
                        Text(secondary)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .card(cornerRadius: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(isNew ? 0.45 : 0), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96))
        .accessibilityLabel("Prefer \(name)")
    }
}

// MARK: - Previews

#Preview("Movies") {
    let snapshot = RankingSession.ListSnapshot(bucketContents: [
        .loved: [
            .init(id: UUID(), name: "The Dark Knight", imageURLString: nil, secondaryText: "2008"),
            .init(id: UUID(), name: "Pulp Fiction", imageURLString: nil, secondaryText: "1994")
        ]
    ])
    let session = RankingSession(snapshot: snapshot, newItemID: UUID())
    session.selectBucket(.loved)
    return ComparisonScreen(
        newItemName: "Poor Things",
        newItemSecondaryText: "2023",
        category: .movies,
        session: session,
        onAnswer: { _ in }
    )
}

#Preview("Restaurants") {
    let snapshot = RankingSession.ListSnapshot(bucketContents: [
        .loved: [
            .init(id: UUID(), name: "Bestia", imageURLString: nil, secondaryText: "2121 E 7th Pl, Los Angeles, CA"),
            .init(id: UUID(), name: "Republique", imageURLString: nil, secondaryText: "624 S La Brea Ave, Los Angeles, CA")
        ]
    ])
    let session = RankingSession(snapshot: snapshot, newItemID: UUID())
    session.selectBucket(.loved)
    return ComparisonScreen(
        newItemName: "Sushi Note",
        newItemSecondaryText: "13447 Ventura Blvd, Sherman Oaks, CA",
        category: .restaurants,
        session: session,
        onAnswer: { _ in }
    )
}
