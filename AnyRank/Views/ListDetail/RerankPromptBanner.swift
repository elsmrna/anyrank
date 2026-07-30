import SwiftUI

/// Inline banner offered after every N additions, asking if the user wants
/// to re-check an item's ranking. Spec § 5.
struct RerankPromptBanner: View {
    let list: RankList
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Time for a re-check?", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
            Text("You've added \(list.additionsSinceLastRerankPrompt) items since the last check. Want to re-rank an older item to keep things accurate?")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Re-rank one", action: onAccept)
                    .buttonStyle(.borderedProminent)
                Button("Not now", action: onDismiss)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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
        .environment(repo)
}
