import SwiftUI

/// Phase 4 of add-item: confirmation screen showing the resulting bucket.
///
/// Auto-dismisses shortly after appearing. The user just picked their
/// sentiment and answered a couple of comparisons; making them tap a
/// "Done" button on top of that is friction we don't need. Instead we
/// show a satisfying checkmark that pops in, hold for a beat, and then
/// return them to the list.
///
/// The numeric score is deliberately hidden here — the user's on a
/// completion screen, not a report; showing a float like "7.4" invites
/// "why that number?" scrutiny that doesn't help. Score surfaces later
/// in the list view once the bucket has 3+ items, per the same rule
/// that governs list rendering.
struct AddItemResultScreen: View {
    let stagedName: String
    let placement: RankingSession.Placement
    let onDone: () -> Void
    /// How long the screen holds before continuing on its own.
    var holdDuration: Duration = Self.defaultHold

    /// How long the screen stays visible after the checkmark animates
    /// in. Long enough to register as a "done" moment, short enough
    /// not to feel like waiting. There's deliberately no "tap to
    /// continue" prompt: it reads as an instruction, when the screen
    /// moves on by itself.
    static let defaultHold: Duration = .milliseconds(1100)

    /// Drives the checkmark scale/opacity animation. Starts false so we
    /// can animate to true on appear.
    @State private var showCheckmark: Bool = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Bucket-tinted rings with the bucket glyph. The halo breathes
            // out as the badge springs in.
            ZStack {
                Circle()
                    .fill(placement.bucket.color.opacity(0.10))
                    .frame(width: 180, height: 180)
                    .scaleEffect(showCheckmark ? 1 : 0.6)
                Circle()
                    .fill(placement.bucket.color.opacity(0.18))
                    .frame(width: 128, height: 128)
                Circle()
                    .fill(placement.bucket.color)
                    .frame(width: 84, height: 84)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.onAccent)
                    }
                    .scaleEffect(showCheckmark ? 1 : 0.2)
                    .opacity(showCheckmark ? 1 : 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Added to \(placement.bucket.displayName)")

            VStack(spacing: 10) {
                Text(stagedName)
                    .font(.display(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                BucketTag(bucket: placement.bucket)
            }
            .opacity(showCheckmark ? 1 : 0)
            .offset(y: showCheckmark ? 0 : 10)

            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Tapping anywhere skips the wait, for anyone who tries.
        .onTapGesture { onDone() }
        .sensoryFeedback(.success, trigger: showCheckmark)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                showCheckmark = true
            }
        }
        .task {
            try? await Task.sleep(for: holdDuration)
            guard !Task.isCancelled else { return }
            onDone()
        }
    }
}

#Preview {
    AddItemResultScreen(
        stagedName: "Sushi Note",
        placement: .init(bucket: .loved, rankInBucket: 1, comparisons: [
            .init(winnerItemID: UUID(), loserItemID: UUID(), kind: .binarySearch),
            .init(winnerItemID: UUID(), loserItemID: UUID(), kind: .binarySearch),
        ]),
        onDone: {}
    )
}
