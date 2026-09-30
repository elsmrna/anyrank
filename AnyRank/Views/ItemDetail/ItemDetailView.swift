import SwiftUI

/// Detail and edit screen for a single item.
struct ItemDetailView: View {
    let item: RankItem
    let list: RankList

    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var rerankPresented = false
    @State private var deleteConfirmation = false
    @State private var dateConsumedDraft: Date

    init(item: RankItem, list: RankList) {
        self.item = item
        self.list = list
        self._dateConsumedDraft = State(initialValue: item.dateConsumed ?? Date())
    }

    var body: some View {
        Form {
            Group {
                Section {
                    hero
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

                Section {
                    TextField("Name", text: nameBinding)
                        .font(.body.weight(.medium))
                } header: {
                    header("Name")
                }

                categoryMetadataSection

                Section {
                    Toggle(isOn: dateBinding.animation(Theme.spring)) {
                        Label("Track date", systemImage: "calendar")
                    }
                    if item.dateConsumed != nil {
                        DatePicker(
                            "Date",
                            selection: $dateConsumedDraft,
                            displayedComponents: .date
                        )
                        .onChange(of: dateConsumedDraft) { _, newValue in
                            item.dateConsumed = newValue
                            repository.touch(list)
                        }
                    }
                } header: {
                    header(visitedHeader)
                }

                Section {
                    TextField("What stood out?", text: notesBinding, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    header("Notes")
                }

                Section {
                    Button(role: .destructive) {
                        deleteConfirmation = true
                    } label: {
                        Text("Delete from list")
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(Theme.danger)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .tint(Theme.accent)
        .themedList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $rerankPresented) {
            RerankFlow(item: item, list: list)
        }
        .confirmationDialog(
            "Delete \(item.name)?",
            isPresented: $deleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the item from the list and renormalizes the bucket's scores.")
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            if list.category.hasArtwork {
                ArtworkView(
                    urlString: RankingApplier.comparisonImageURLString(for: item, in: list),
                    category: list.category,
                    width: list.category.artworkAspectRatio == 1 ? 150 : 120,
                    cornerRadius: 14
                )
                .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
            } else {
                CategoryIconTile(category: list.category, size: 72)
            }

            VStack(spacing: 6) {
                Text(item.name)
                    .font(.display(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                if let secondary = RankingApplier.comparisonSecondaryText(for: item, in: list) {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 10) {
                BucketTag(bucket: item.bucket)
                if item.shouldDisplayScore {
                    Text(String(format: "%.1f", item.score))
                        .font(.score(.title2, weight: .bold))
                        .foregroundStyle(item.bucket.ink)
                }
                if let rankLine {
                    Text(rankLine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if !item.shouldDisplayScore {
                Text("A score appears once \(item.bucket.displayName) has 3 items.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 10) {
                Button {
                    rerankPresented = true
                } label: {
                    Label("Re-rank", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(HeroActionStyle(prominent: true))
                .labelStyle(TightLabelStyle())

                if let url = item.primaryURL {
                    Link(destination: url) {
                        Label(linkLabel, systemImage: "arrow.up.right")
                    }
                    .buttonStyle(HeroActionStyle(prominent: false))
                    .labelStyle(TightLabelStyle())
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var rankLine: String? {
        let sorted = list.itemsSortedByScore()
        guard let index = sorted.firstIndex(where: { $0.id == item.id }) else { return nil }
        return "#\(index + 1) of \(sorted.count)"
    }

    private var linkLabel: String {
        switch list.category {
        case .restaurants, .bars: return "Maps"
        case .movies:             return "IMDb"
        case .books:              return "StoryGraph"
        case .anime:              return "AniList"
        case .games:              return "IGDB"
        case .albums, .songs:     return "Spotify"
        case .custom:             return item.mapsURLString != nil ? "Maps" : "Open link"
        }
    }

    private var visitedHeader: String {
        switch list.category {
        case .restaurants, .bars: return "Visited"
        case .movies, .anime:     return "Watched"
        case .books:              return "Read"
        case .games:              return "Played"
        case .albums, .songs:     return "Listened"
        case .custom:             return "Date"
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder
    private var categoryMetadataSection: some View {
        switch list.category {
        case .restaurants, .bars:
            // The address is already under the name in the hero, and the
            // Maps button links out — nothing more to show here.
            EmptyView()
        case .movies:
            Section("Movie") {
                if let year = item.releaseYear {
                    LabeledContent("Year", value: String(year))
                }
            }
        case .books:
            Section("Book") {
                if let author = item.author {
                    LabeledContent("Author", value: author)
                }
                if let year = item.releaseYear {
                    LabeledContent("Published", value: String(year))
                }
                if let isbn = item.isbn {
                    LabeledContent("ISBN", value: isbn)
                }
            }
        case .anime:
            Section("Anime") {
                if let format = item.animeFormat {
                    LabeledContent("Format", value: format.capitalized)
                }
                if let year = item.releaseYear {
                    LabeledContent("Year", value: String(year))
                }
                if let eps = item.episodeCount {
                    LabeledContent("Episodes", value: String(eps))
                }
            }
        case .games:
            Section("Game") {
                if let year = item.releaseYear {
                    LabeledContent("Year", value: String(year))
                }
                if let platforms = item.platforms, !platforms.isEmpty {
                    LabeledContent("Platforms", value: platforms.joined(separator: ", "))
                }
            }
        case .albums:
            Section("Album") {
                if let artist = item.artist {
                    LabeledContent("Artist", value: artist)
                }
                if let year = item.releaseYear {
                    LabeledContent("Year", value: String(year))
                }
            }
        case .songs:
            Section("Song") {
                if let artist = item.artist {
                    LabeledContent("Artist", value: artist)
                }
                if let album = item.albumTitle {
                    LabeledContent("Album", value: album)
                }
                if let year = item.releaseYear {
                    LabeledContent("Year", value: String(year))
                }
                if let duration = item.durationSeconds {
                    let mins = duration / 60
                    let secs = duration % 60
                    LabeledContent("Length", value: String(format: "%d:%02d", mins, secs))
                }
            }
        case .custom:
            // Maps-linked custom lists show the same Place section as
            // Restaurants/Bars — the address and Maps URL came from the
            // picker, not free-form entry, so they read as static facts
            // rather than editable fields.
            if list.linksToMapsLocation {
                if !list.customFieldNames.isEmpty {
                    Section("Custom fields") {
                        ForEach(list.customFieldNames, id: \.self) { field in
                            TextField(field, text: customFieldBinding(field))
                        }
                    }
                }
            } else {
                Section("Details") {
                    TextField("Link", text: customLinkBinding)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !list.customFieldNames.isEmpty {
                        ForEach(list.customFieldNames, id: \.self) { field in
                            TextField(field, text: customFieldBinding(field))
                        }
                    }
                }
            }
        }
    }

    // MARK: Bindings that persist on every edit

    private var nameBinding: Binding<String> {
        Binding(get: { item.name }, set: { newValue in
            item.name = newValue
            repository.touch(list)
        })
    }

    private var notesBinding: Binding<String> {
        Binding(get: { item.notes }, set: { newValue in
            item.notes = newValue
            repository.touch(list)
        })
    }

    private var customLinkBinding: Binding<String> {
        Binding(
            get: { item.customLinkString ?? "" },
            set: { newValue in
                item.customLinkString = newValue.isEmpty ? nil : newValue
                repository.touch(list)
            }
        )
    }

    private func customFieldBinding(_ field: String) -> Binding<String> {
        Binding(
            get: { item.customFieldValues[field] ?? "" },
            set: { newValue in
                item.customFieldValues[field] = newValue.isEmpty ? nil : newValue
                repository.touch(list)
            }
        )
    }

    private var dateBinding: Binding<Bool> {
        Binding(
            get: { item.dateConsumed != nil },
            set: { isOn in
                if isOn {
                    item.dateConsumed = dateConsumedDraft
                } else {
                    item.dateConsumed = nil
                }
                repository.touch(list)
            }
        )
    }

    private func performDelete() {
        RankingApplier.delete(item: item, from: list, repository: repository)
        dismiss()
    }
}

/// Capsule action under the item hero — prominent (terracotta) or quiet.
private struct HeroActionStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Theme.onAccent : Theme.textPrimary)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(prominent ? Theme.accent : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: prominent ? 0 : 0.5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

#Preview("Restaurants") {
    let repo = PreviewSupport.fullRestaurantsRepository()
    let list = repo.lists.first!
    let item = list.itemsSortedByScore().first!
    return NavigationStack {
        ItemDetailView(item: item, list: list)
    }
    .environment(repo)
}

#Preview("Custom — Maps-linked") {
    let repo = PreviewSupport.customMapsLinkedRepository()
    let list = repo.lists.first!
    let item = list.itemsSortedByScore().first!
    return NavigationStack {
        ItemDetailView(item: item, list: list)
    }
    .environment(repo)
}
