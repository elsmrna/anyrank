import SwiftUI
import UniformTypeIdentifiers

/// Working state shared across the import sheet's steps.
@Observable
final class ImportDraft {
    enum Target: Hashable {
        case newList
        case existing(UUID)
    }

    var source: ImportSourceKind = .steam
    /// For a pasted list without a fixed target, the category chosen.
    var pastedCategory: Category = .custom
    var candidates: [ImportCandidate] = []
    var target: Target = .newList
    var newListName = ""
    var skipNeverEngaged = true

    var category: Category { source.category ?? pastedCategory }
}

/// Sheet for a one-time import: pick a source, provide input, preview what
/// will be queued, then start ranking (or save the queue for later).
struct ImportFlowView: View {
    /// Importing from a list's menu fixes the target; from Home, the user
    /// chooses a new or existing list on the preview step.
    let targetList: RankList?

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ImportDraft()
    @State private var path: [Step] = []

    enum Step: Hashable {
        case input
        case preview
    }

    init(targetList: RankList? = nil) {
        self.targetList = targetList
    }

    var body: some View {
        NavigationStack(path: $path) {
            ImportSourcePicker(targetList: targetList) { source in
                draft.source = source
                if let targetList {
                    draft.pastedCategory = targetList.category
                    draft.target = .existing(targetList.id)
                }
                draft.newListName = source.defaultListName
                path.append(.input)
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: Step.self) { step in
                Group {
                    switch step {
                    case .input:
                        input
                    case .preview:
                        // Pass the sheet's own dismiss: `dismiss` read inside a
                        // pushed screen pops the stack instead of closing.
                        ImportPreviewScreen(draft: draft, targetList: targetList, close: { dismiss() })
                    }
                }
                .screenBackground()
                .navigationBarTitleDisplayMode(.inline)
            }
            .screenBackground()
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.background)
    }

    @ViewBuilder
    private var input: some View {
        let loaded: ([ImportCandidate]) -> Void = { candidates in
            draft.candidates = candidates
            path.append(.preview)
        }
        switch draft.source {
        case .steam:
            SteamInputScreen(onLoaded: loaded)
        case .letterboxd, .goodreads, .storyGraph:
            FileInputScreen(source: draft.source, onLoaded: loaded)
        case .pastedList:
            PasteInputScreen(draft: draft, categoryIsFixed: targetList != nil, onLoaded: loaded)
        }
    }
}

// MARK: - Source picker

private struct ImportSourcePicker: View {
    let targetList: RankList?
    let onPick: (ImportSourceKind) -> Void

    private var sources: [ImportSourceKind] {
        ImportSourceKind.allCases.filter { source in
            targetList.map { source.canTarget($0.category) } ?? true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bring in a collection")
                        .font(.display(.title))
                        .foregroundStyle(Theme.textPrimary)
                    Text(targetList.map { "New finds go into \u{201C}\($0.name)\u{201D}. Anything already there is skipped, and you rank the rest at your own pace." }
                         ?? "Pull in everything at once, then rank it at your own pace — a few now, the rest whenever you come back.")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                VStack(spacing: 10) {
                    ForEach(sources) { source in
                        Button {
                            onPick(source)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: source.systemImage)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(source.category?.tint ?? Theme.taupe)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        (source.category?.tint ?? Theme.taupe).opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.displayName)
                                        .font(.headline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(source.tagline)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(14)
                            .card()
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Steam

private struct SteamInputScreen: View {
    let onLoaded: ([ImportCandidate]) -> Void

    @Environment(\.steamLibraryService) private var steam
    @AppStorage("import.steamProfile") private var profile = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InputHeader(source: .steam, detail: "We'll read the games you own and queue them up, most-played first.")

                VStack(alignment: .leading, spacing: 8) {
                    TextField("steamcommunity.com/id/yourname", text: $profile)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit(fetch)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                    Text("Your profile URL, custom URL name, or SteamID. Your profile's Game details must be set to Public.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }

                if steam.isSample {
                    Label("No Steam Web API key is configured in this build, so this imports a sample library.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let errorMessage {
                    ErrorText(errorMessage)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: fetch) {
                if isLoading {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Text("Get my library")
                }
            }
            .buttonStyle(.primary)
            .disabled(isLoading || profile.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 8)
            .background(Theme.background)
        }
        .onAppear { focused = profile.isEmpty }
    }

    private func fetch() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        focused = false
        Task {
            defer { isLoading = false }
            do {
                let games = try await steam.ownedGames(profile: profile)
                onLoaded(SteamImport.candidates(from: games))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - CSV exports

private struct FileInputScreen: View {
    let source: ImportSourceKind
    let onLoaded: ([ImportCandidate]) -> Void

    @State private var choosingFile = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InputHeader(source: source, detail: detail)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.score(.footnote, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24, height: 24)
                                .background(Theme.accent.opacity(0.14), in: Circle())
                            Text(step)
                                .font(.callout)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if let errorMessage {
                    ErrorText(errorMessage)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Choose CSV file") { choosingFile = true }
                .buttonStyle(.primary)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 8)
                .background(Theme.background)
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            load(result)
        }
    }

    private var detail: String {
        switch source {
        case .letterboxd: return "Every film you've logged, highest-rated first. Your star ratings show up as suggestions while you rank."
        case .goodreads:  return "Books on your Read shelf, highest-rated first. Your star ratings show up as suggestions while you rank."
        case .storyGraph: return "Books you've finished, highest-rated first. Your star ratings show up as suggestions while you rank."
        default:          return ""
        }
    }

    private var steps: [String] {
        switch source {
        case .letterboxd:
            return ["On letterboxd.com, open Settings → Import & Export.",
                    "Tap Export your data and unzip the download.",
                    "Choose diary.csv, ratings.csv, or watched.csv."]
        case .goodreads:
            return ["On goodreads.com, open My Books → Import and export.",
                    "Tap Export Library and download the file.",
                    "Choose the goodreads_library_export.csv file."]
        case .storyGraph:
            return ["On thestorygraph.com, open Manage Account.",
                    "Tap Export StoryGraph Library and download the file.",
                    "Choose the exported .csv file."]
        default:
            return []
        }
    }

    private func load(_ result: Result<URL, Error>) {
        errorMessage = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            let candidates = try FileImporters.candidates(from: text, source: source, category: source.category ?? .custom)
            onLoaded(candidates)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Pasted list

private struct PasteInputScreen: View {
    @Bindable var draft: ImportDraft
    let categoryIsFixed: Bool
    let onLoaded: ([ImportCandidate]) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var candidates: [ImportCandidate] {
        FileImporters.pastedList(text, category: draft.category)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InputHeader(source: .pastedList, detail: "Paste one item per line — from a note, a spreadsheet column, anywhere. Numbers and bullets are cleaned up.")

                if !categoryIsFixed {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("What are these?")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(Category.allCases) { category in
                                CategoryChip(category: category, isSelected: draft.pastedCategory == category) {
                                    withAnimation(Theme.spring) { draft.pastedCategory = category }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Spirited Away\nPerfect Blue\nYour Name")
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .focused($focused)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                    }
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))

                    if !candidates.isEmpty {
                        Text("\(candidates.count) \(candidates.count == 1 ? "item" : "items")")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button("Continue") { onLoaded(candidates) }
                .buttonStyle(.primary)
                .disabled(candidates.isEmpty)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 8)
                .background(Theme.background)
        }
    }
}

// MARK: - Preview

private struct ImportPreviewScreen: View {
    @Bindable var draft: ImportDraft
    let targetList: RankList?
    /// Closes the whole import sheet.
    let close: () -> Void

    @Environment(Repository.self) private var repository
    @Environment(\.importStore) private var store
    @Environment(\.router) private var router

    private var resolvedTarget: RankList? {
        if let targetList { return targetList }
        if case .existing(let id) = draft.target {
            return repository.lists.first { $0.id == id }
        }
        return nil
    }

    private var plan: ImportPlan {
        ImportMatcher.plan(
            candidates: draft.candidates,
            target: resolvedTarget,
            alreadyQueued: resolvedTarget.flatMap { store.session(for: $0.id)?.pending } ?? [],
            skipNeverEngaged: draft.skipNeverEngaged
        )
    }

    /// Existing lists this import could go into.
    private var compatibleLists: [RankList] {
        repository.lists.filter { $0.category == draft.category }
    }

    private var neverEngagedCount: Int {
        draft.candidates.filter(\.neverEngaged).count
    }

    var body: some View {
        let plan = plan
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summary(plan)
                breakdown(plan)
                if targetList == nil {
                    targetPicker
                }
                if let target = resolvedTarget, store.session(for: target.id) != nil {
                    Label("\u{201C}\(target.name)\u{201D} already has an import in progress. New items join the end of its queue.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(Theme.spring, value: plan.toRank.count)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button("Start ranking") { commit(plan, startNow: true) }
                    .buttonStyle(.primary)
                Button("Save for later") { commit(plan, startNow: false) }
                    .buttonStyle(.secondary)
            }
            .disabled(plan.toRank.isEmpty || !canCommit)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 8)
            .background(Theme.background)
        }
    }

    private var canCommit: Bool {
        if resolvedTarget != nil { return true }
        return !draft.newListName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func summary(_ plan: ImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(plan.toRank.count)")
                .font(.system(size: 56, weight: .bold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(plan.toRank.isEmpty
                 ? "Nothing new to rank — everything here is already in the list."
                 : "\(plan.toRank.count == 1 ? draft.category.itemNoun : pluralNoun) to rank. You can stop any time and pick up where you left off.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func breakdown(_ plan: ImportPlan) -> some View {
        VStack(spacing: 0) {
            row("Found in \(draft.source.displayName)", "\(plan.found)")
            if plan.alreadyInList > 0 {
                Divider().overlay(Theme.hairline)
                row("Already in the list", "\(plan.alreadyInList)")
            }
            if plan.alreadyQueued > 0 {
                Divider().overlay(Theme.hairline)
                row("Already queued", "\(plan.alreadyQueued)")
            }
            if plan.repeatedInSource > 0 {
                Divider().overlay(Theme.hairline)
                row("Duplicates in the export", "\(plan.repeatedInSource)")
            }
            if neverEngagedCount > 0 {
                Divider().overlay(Theme.hairline)
                Toggle(isOn: $draft.skipNeverEngaged.animation(Theme.spring)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip games you've never played")
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(neverEngagedCount) in your library")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16)
        .card()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(.score(.body, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 13)
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Add to")
            VStack(spacing: 0) {
                targetRow(.newList) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A new list").foregroundStyle(Theme.textPrimary)
                        if draft.target == .newList {
                            TextField("List name", text: $draft.newListName)
                                .font(.body.weight(.medium))
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 12)
                                .frame(height: 40)
                                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                ForEach(compatibleLists) { list in
                    Divider().overlay(Theme.hairline)
                    targetRow(.existing(list.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name).foregroundStyle(Theme.textPrimary)
                            Text("\(list.items.count) \(list.items.count == 1 ? "item" : "items")")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .card()
        }
    }

    private func targetRow<Content: View>(_ target: ImportDraft.Target, @ViewBuilder content: () -> Content) -> some View {
        Button {
            withAnimation(Theme.spring) { draft.target = target }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: draft.target == target ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(draft.target == target ? Theme.accent : Theme.hairline)
                content()
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pluralNoun: String {
        switch draft.category {
        case .anime:  return "anime"
        case .custom: return "items"
        default:      return draft.category.itemNoun + "s"
        }
    }

    private func commit(_ plan: ImportPlan, startNow: Bool) {
        let list: RankList
        if let target = resolvedTarget {
            list = target
        } else {
            list = RankList(
                name: draft.newListName.trimmingCharacters(in: .whitespaces),
                category: draft.category
            )
            repository.addList(list)
        }
        store.enqueue(plan.toRank, into: list.id, from: draft.source)
        close()
        if startNow {
            router.openAndRank(list.id)
        } else if targetList == nil {
            router.path = [list.id]
        }
    }
}

// MARK: - Shared bits

private struct InputHeader: View {
    let source: ImportSourceKind
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source.displayName)
                .font(.display(.title))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }
}

private struct ErrorText: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(Theme.danger)
            .fixedSize(horizontal: false, vertical: true)
    }
}
