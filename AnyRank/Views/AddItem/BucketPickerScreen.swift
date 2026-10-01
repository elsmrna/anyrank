import SwiftUI

/// Phase 2 of add-item: the user picks a sentiment bucket. Four big tap
/// targets, one per bucket, each with its color, glyph, and a short
/// description so the choice is quick and unambiguous.
///
/// When the item's details are known (artwork, year, a note from an import
/// source) they're shown in a card under the question, and a bucket the
/// source's own rating points to is marked "Suggested" — a hint, never a
/// default. Import sprees also get skip / remove actions at the bottom.
struct BucketPickerScreen: View {
    let itemName: String
    var artworkURLString: String? = nil
    /// Set to show the rich item card instead of just the name.
    var category: Category? = nil
    var secondaryText: String? = nil
    var suggestedBucket: Bucket? = nil
    /// Tag text on the suggested bucket ("Current" when re-ranking).
    var suggestionLabel: String = "Suggested"
    var sourceNote: String? = nil
    /// "Skip for now" — shown only when provided.
    var onSkip: (() -> Void)? = nil
    /// "Not this one" — shown only when provided.
    var onRemove: (() -> Void)? = nil
    let onPick: (Bucket) -> Void

    @State private var picked: Bucket?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    ForEach(Bucket.orderedHighToLow) { bucket in
                        BucketButton(
                            bucket: bucket,
                            isPicked: picked == bucket,
                            isSuggested: suggestedBucket == bucket,
                            suggestionLabel: suggestionLabel
                        ) {
                            picked = bucket
                            onPick(bucket)
                        }
                    }
                }

                if onSkip != nil || onRemove != nil {
                    queueActions
                } else {
                    Text("Next, you'll compare it with a few things you've already ranked.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .screenBackground()
        .sensoryFeedback(.selection, trigger: picked)
        // Clear the highlight when the user comes back to this screen.
        .onAppear { picked = nil }
    }

    @ViewBuilder
    private var header: some View {
        if let category {
            VStack(alignment: .leading, spacing: 16) {
                Text("How was it?")
                    .font(.display(.largeTitle))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 14) {
                    if category.hasArtwork {
                        ArtworkView(urlString: artworkURLString, category: category, width: 56, cornerRadius: 8)
                    } else {
                        CategoryIconTile(category: category, size: 48)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(itemName)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        if let secondaryText, !secondaryText.isEmpty {
                            Text(secondaryText)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        if let sourceNote {
                            Text(sourceNote)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .card()
                // Artwork can arrive after the screen appears (import
                // enrichment); let it fade in rather than pop.
                .animation(.easeOut(duration: 0.25), value: artworkURLString)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("How was it?")
                    .font(.display(.largeTitle))
                    .foregroundStyle(Theme.textPrimary)
                Text(itemName)
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    private var queueActions: some View {
        HStack(spacing: 10) {
            if let onSkip {
                Button(action: onSkip) {
                    Label("Skip for now", systemImage: "arrow.uturn.forward")
                }
                .buttonStyle(QueueActionStyle())
            }
            if let onRemove {
                Button(action: onRemove) {
                    Label("Not this one", systemImage: "xmark")
                }
                .buttonStyle(QueueActionStyle())
            }
        }
        .labelStyle(TightLabelStyle())
        .frame(maxWidth: .infinity)
    }
}

private struct QueueActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Theme.surfaceMuted, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

private struct BucketButton: View {
    let bucket: Bucket
    let isPicked: Bool
    var isSuggested: Bool = false
    var suggestionLabel: String = "Suggested"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: bucket.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isPicked ? Theme.onAccent : bucket.color)
                    .frame(width: 48, height: 48)
                    .background(isPicked ? bucket.color : bucket.color.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(bucket.displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if isSuggested {
                            Text(suggestionLabel)
                                .font(.caption2.weight(.bold))
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .foregroundStyle(bucket.ink)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(bucket.color.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(bucket.blurb)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(bucket.color.opacity(isPicked ? 1 : (isSuggested ? 0.5 : 0)), lineWidth: isPicked ? 2 : 1)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(bucket.displayName): \(bucket.blurb)\(isSuggested ? ", \(suggestionLabel.lowercased())" : "")")
    }
}

#Preview {
    NavigationStack {
        BucketPickerScreen(itemName: "Bestia", onPick: { _ in })
    }
}

#Preview("Import item") {
    NavigationStack {
        BucketPickerScreen(
            itemName: "Hollow Knight",
            category: .games,
            secondaryText: "2017",
            suggestedBucket: .liked,
            sourceNote: "44 hours played",
            onSkip: {},
            onRemove: {},
            onPick: { _ in }
        )
    }
}
