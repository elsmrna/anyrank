import SwiftUI

/// Shown at the top of a list with an unfinished import: how far along it
/// is, what's coming up, and a way to abandon it.
struct ImportProgressCard: View {
    let session: ImportSession
    let category: Category
    let onAbandon: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SourceIcon(source: session.source, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.source.displayName) import")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(session.rankedCount) of \(session.total) ranked · \(session.pending.count) to go")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 8)
                Menu {
                    Button(role: .destructive, action: onAbandon) {
                        Label("Abandon import", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Import options")
            }

            ProgressView(value: session.progress)
                .progressViewStyle(QueueProgressStyle())

            if category.hasArtwork {
                upNext
            }
        }
        .padding(16)
        .card()
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
