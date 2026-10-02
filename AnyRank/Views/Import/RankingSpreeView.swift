import SwiftUI

/// Works through a list's import queue one item at a time, each through the
/// normal bucket pick → comparisons flow, advancing automatically after
/// each placement.
///
/// Pausing is just closing the sheet: the queue is persisted, every placed
/// item is already saved, and only the item on screen restarts next time.
struct RankingSpreeView: View {
    let list: RankList

    @Environment(\.importStore) private var store
    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @Environment(\.movieService) private var movieService
    @Environment(\.bookService) private var bookService
    @Environment(\.animeService) private var animeService
    @Environment(\.mangaService) private var mangaService
    @Environment(\.gameService) private var gameService
    @Environment(\.musicService) private var musicService

    @State private var coordinator: AddItemCoordinator?
    @State private var completion: Completion?
    @State private var rankedThisSitting = 0
    /// Items we've already tried to enrich this sitting, hit or miss.
    @State private var lookedUp: Set<UUID> = []

    private struct Completion {
        let ranked: Int
        let removed: Int
    }

    private var session: ImportSession? { store.session(for: list.id) }

    var body: some View {
        ZStack {
            if let coordinator, let session, let staged = coordinator.staged {
                PlacementFlowView(
                    coordinator: coordinator,
                    rootTitle: "\(session.handledCount + 1) of \(session.total)",
                    newItemImageURLString: \.artworkURLString,
                    newItemSecondaryText: \.secondaryText,
                    onCommit: commit,
                    cancelTitle: "Pause",
                    afterCommit: advance,
                    resultHold: .milliseconds(900)
                ) {
                    BucketPickerScreen(
                        itemName: staged.name,
                        artworkURLString: staged.artworkURLString,
                        category: list.category,
                        secondaryText: staged.secondaryText,
                        suggestedBucket: staged.suggestedBucket,
                        sourceNote: staged.sourceNote,
                        sourceBrand: ServiceBrand(session.source),
                        onSkip: session.pending.count > 1 ? { skip(staged) } : nil,
                        onRemove: { remove(staged) }
                    ) { bucket in
                        coordinator.bucketPicked(bucket)
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        ProgressView(value: session.progress)
                            .progressViewStyle(QueueProgressStyle())
                            .padding(.horizontal, Theme.gutter)
                            .padding(.bottom, 4)
                    }
                }
                .id(staged.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else if let completion {
                completionView(completion)
                    .transition(.opacity)
            }
        }
        .screenBackground()
        .presentationBackground(Theme.background)
        .onAppear { if coordinator == nil { advance() } }
        .task(id: coordinator?.staged?.id) { await enrichUpcoming() }
    }

    // MARK: Queue actions

    /// Move to the head of the queue, skipping anything that's since been
    /// added to the list by hand.
    private func advance() {
        while let head = session?.pending.first, ImportMatcher.list(list, contains: head) {
            store.discardDuplicate(head.id, from: list.id)
        }
        withAnimation(Theme.spring) {
            if let head = session?.pending.first {
                coordinator = AddItemCoordinator(placing: head, in: list)
            } else {
                coordinator = nil
                if completion == nil {
                    completion = Completion(ranked: rankedThisSitting, removed: 0)
                }
            }
        }
    }

    private func commit(_ staged: StagedItem, _ placement: RankingSession.Placement) {
        noteCompletionIfLast(ranked: true)
        let item = RankItem(id: staged.id, name: staged.name, bucket: placement.bucket)
        staged.apply(to: item)
        RankingApplier.apply(placement: placement, item: item, list: list, repository: repository)
        store.markRanked(staged.id, in: list.id)
        rankedThisSitting += 1
    }

    private func skip(_ staged: StagedItem) {
        store.deferItem(staged.id, in: list.id)
        advance()
    }

    private func remove(_ staged: StagedItem) {
        noteCompletionIfLast(ranked: false)
        store.remove(staged.id, from: list.id)
        advance()
    }

    /// Capture totals before the last item leaves the queue (the session is
    /// removed once it empties).
    private func noteCompletionIfLast(ranked: Bool) {
        guard let session, session.pending.count == 1 else { return }
        completion = Completion(
            ranked: session.rankedCount + (ranked ? 1 : 0),
            removed: session.removedCount + (ranked ? 0 : 1)
        )
    }

    // MARK: Enrichment

    /// Look up artwork/links for the current item and the next couple, so
    /// covers are usually ready by the time an item comes up.
    private func enrichUpcoming() async {
        let enricher = ImportEnricher(
            movies: movieService, books: bookService, anime: animeService, manga: mangaService,
            games: gameService, music: musicService
        )
        let upcoming = (session?.pending.prefix(3) ?? []).filter { !lookedUp.contains($0.id) }
        for item in upcoming {
            guard !Task.isCancelled else { return }
            lookedUp.insert(item.id)
            guard let enriched = await enricher.enrich(item) else { continue }
            store.update(enriched, in: list.id)
            coordinator?.updateStaged(enriched)
        }
    }

    // MARK: Completion

    private func completionView(_ completion: Completion) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 84, height: 84)
                .background(Theme.accent, in: Circle())
                .background(Theme.accent.opacity(0.14), in: Circle().inset(by: -22))
            VStack(spacing: 10) {
                Text("All caught up")
                    .font(.display(.largeTitle))
                    .foregroundStyle(Theme.textPrimary)
                Text(completionLine(completion))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.primary)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 8)
    }

    private func completionLine(_ completion: Completion) -> String {
        let noun = completion.ranked == 1 ? list.category.itemNoun : pluralNoun
        var line = "\(completion.ranked) \(noun) ranked into \u{201C}\(list.name)\u{201D}."
        if completion.removed > 0 {
            line += " \(completion.removed) left out."
        }
        return line
    }

    private var pluralNoun: String { list.category.pluralNoun }
}

/// Thin progress bar for the import queue.
struct QueueProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(6, geo.size.width * (configuration.fractionCompleted ?? 0)))
            }
        }
        .frame(height: 4)
        .animation(Theme.spring, value: configuration.fractionCompleted)
    }
}
