import SwiftUI

/// Phase 2 of add-item: the user picks a sentiment bucket. Four big tap
/// targets, one per bucket, each with its color, glyph, and a short
/// description so the choice is quick and unambiguous.
struct BucketPickerScreen: View {
    let itemName: String
    let onPick: (Bucket) -> Void

    @State private var picked: Bucket?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How was it?")
                        .font(.display(.largeTitle))
                        .foregroundStyle(Theme.textPrimary)
                    Text(itemName)
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                .padding(.top, 8)

                VStack(spacing: 12) {
                    ForEach(Bucket.orderedHighToLow) { bucket in
                        BucketButton(bucket: bucket, isPicked: picked == bucket) {
                            picked = bucket
                            onPick(bucket)
                        }
                    }
                }

                Text("Next, you'll compare it with a few things you've already ranked.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
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
}

private struct BucketButton: View {
    let bucket: Bucket
    let isPicked: Bool
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
                    Text(bucket.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
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
                    .strokeBorder(bucket.color, lineWidth: isPicked ? 2 : 0)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(bucket.displayName): \(bucket.blurb)")
    }
}

#Preview {
    NavigationStack {
        BucketPickerScreen(itemName: "Bestia", onPick: { _ in })
    }
}
