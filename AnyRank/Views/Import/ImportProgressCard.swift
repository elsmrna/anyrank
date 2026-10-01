import SwiftUI

/// Shown at the top of a list with an unfinished import: how far along it
/// is and what's coming up. The whole card continues the ranking spree;
/// its menu holds "Abandon import".
struct ImportProgressCard: View {
    let session: ImportSession
    let category: Category
    let onContinue: () -> Void
    let onAbandon: () -> Void

    var body: some View {
        Button(action: onContinue) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    SourceIcon(source: session.source, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.source.displayName) import")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(session.rankedCount) of \(session.total) ranked")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 44) // room for the menu overlay
                }

                ProgressView(value: session.progress)
                    .progressViewStyle(QueueProgressStyle())

                if category.hasArtwork {
                    upNext
                }

                HStack(spacing: 8) {
                    Text("Continue ranking · \(session.pending.count) left")
                        .contentTransition(.numericText())
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.accent, in: Capsule())
            }
            .padding(16)
            .card()
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityLabel("\(session.source.displayName) import, \(session.rankedCount) of \(session.total) ranked. Continue ranking, \(session.pending.count) left")
        // Outside the button's label so it stays separately tappable.
        .overlay(alignment: .topTrailing) {
            Menu {
                Button(role: .destructive, action: onAbandon) {
                    Label("Abandon import", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Import options")
            .padding(.top, 14)
            .padding(.trailing, 8)
        }
    }

    /// The next few covers, so the queue feels tangible.
    private var upNext: some View {
        HStack(spacing: 8) {
            ForEach(session.pending.prefix(6)) { item in
                ArtworkView(urlString: item.artworkURLString, category: category, width: 38, cornerRadius: 6)
            }
            if session.pending.count > 6 {
                Text("+\(session.pending.count - 6)")
                    .font(.score(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 2)
            }
        }
        .accessibilityHidden(true)
    }
}
