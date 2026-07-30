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

    /// How long the screen stays visible after the checkmark animates
    /// in. Long enough to register as a "done" moment, short enough
    /// not to feel like waiting.
    private static let dismissDelay: Duration = .milliseconds(1100)

    /// Drives the checkmark scale/opacity animation. Starts false so we
    /// can animate to true on appear.
    @State private var showCheckmark: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Bucket-tinted circle with a checkmark. Springs in on appear.
            ZStack {
                Circle()
                    .fill(placement.bucket.color.opacity(0.18))
                    .frame(width: 120, height: 120)
                Circle()
                    .strokeBorder(placement.bucket.color, lineWidth: 3)
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(placement.bucket.color)
                    .scaleEffect(showCheckmark ? 1 : 0.1)
                    .opacity(showCheckmark ? 1 : 0)
            }
            .accessibilityLabel("Added to \(placement.bucket.displayName)")

            VStack(spacing: 6) {
                Text(stagedName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Added to \(placement.bucket.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        // Tap anywhere to bypass the wait. Doesn't hurt to expose an
        // impatience escape hatch even though the auto-dismiss is short.
        .onTapGesture { onDone() }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                showCheckmark = true
            }
            Task {
                try? await Task.sleep(for: Self.dismissDelay)
                onDone()
            }
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
