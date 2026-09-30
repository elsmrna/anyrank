import SwiftUI

/// Inline banner offered after every N additions, asking if the user wants
/// to re-check an item's ranking. Spec § 5.
struct RerankPromptBanner: View {
    let list: RankList
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.olive)
                    .frame(width: 36, height: 36)
                    .background(Theme.olive.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time for a re-check?")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("You've added \(list.additionsSinceLastRerankPrompt) items since the last check. Re-ranking an older one keeps the list honest.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button("Re-rank one", action: onAccept)
                    .buttonStyle(CompactButtonStyle(prominent: true))
                Button("Not now", action: onDismiss)
                    .buttonStyle(CompactButtonStyle(prominent: false))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct CompactButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Theme.onAccent : Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(prominent ? Theme.accent : Theme.surfaceMuted, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

#Preview {
    // Wrap the mid-block mutation in an IIFE so the `#Preview` body
    // stays purely declarative — the ViewBuilder result-builder doesn't
    // accept mid-body statements alongside an explicit `return`.
    let repo = PreviewSupport.fullRestaurantsRepository()
    let list: RankList = {
        let l = repo.lists.first!
        l.additionsSinceLastRerankPrompt = 10
        return l
    }()
    return RerankPromptBanner(list: list, onAccept: {}, onDismiss: {})
        .padding()
        .screenBackground()
        .environment(repo)
}
