import SwiftUI

/// Detail screen for a single item. Facts that came from a catalog (year,
/// author, platforms…) are shown read-only in the hero; only things the
/// user authored — dates, notes, and a custom list's own fields — are
/// editable below it.
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

                customDetailsSection

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Text rather than an icon: the circular-arrows glyph alone
                // doesn't say "re-rank", and this is the screen's key action.
                Button("Re-rank") {
                    rerankPresented = true
                }
                .fontWeight(.semibold)
            }
        }
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
            if list.showsArtwork {
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
                if let subtitle = heroSubtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if !heroFacts.isEmpty {
                    Text(heroFacts.joined(separator: "  ·  "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
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

            if let url = item.primaryURL {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        if let brand = ServiceBrand(url: url) {
                            BrandIcon(brand: brand, size: 20)
                        } else {
                            Image(systemName: "arrow.up.right")
                        }
                        Text("Open in \(linkLabel(for: url))")
                    }
                }
                .buttonStyle(HeroActionStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var rankLine: String? {
        let sorted = list.itemsSortedByScore()
        guard let index = sorted.firstIndex(where: { $0.id == item.id }) else { return nil }
        return "#\(index + 1) of \(sorted.count)"
    }

    /// Named for where the link actually goes — an imported Steam game links
    /// to Steam even though its category's usual destination is IGDB.
    private func linkLabel(for url: URL) -> String {
        if let brand = ServiceBrand(url: url) { return brand.displayName }
        switch list.category {
        case .restaurants, .bars, .stays: return "Maps"
        case .movies, .tv:        return "IMDb"
        case .books:              return "StoryGraph"
        case .anime, .manga:      return "AniList"
        case .games:              return "IGDB"
        case .albums:             return "Spotify"
        case .custom:             return item.mapsURLString != nil ? "Maps" : "browser"
        }
    }

    private var visitedHeader: String {
        switch list.category {
        case .restaurants, .bars: return "Visited"
        case .stays:              return "Stayed"
        case .movies, .tv, .anime: return "Watched"
        case .books, .manga:      return "Read"
        case .games:              return "Played"
        case .albums:             return "Listened"
        case .custom:             return "Date"
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.textSecondary)
    }

    // MARK: Facts

    /// Who made it / where it is — the most identifying fact after the name.
    private var heroSubtitle: String? {
        let value: String?
        switch list.category {
        case .restaurants, .bars, .stays, .custom: value = item.address
        case .books:                       value = item.author
        case .albums:                      value = item.artist
        case .movies, .tv, .anime, .manga, .games: value = nil
        }
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Smaller supporting facts, joined into one line under the subtitle.
    private var heroFacts: [String] {
        var facts: [String] = []
        switch list.category {
        case .anime:
            if let format = item.animeFormat, !format.isEmpty {
                facts.append(format.count <= 3 ? format.uppercased() : format.capitalized)
            }
        case .manga:
            if let format = item.animeFormat, !format.isEmpty { facts.append(format) }
        default:
            break
        }
        if let year = item.releaseYear { facts.append(String(year)) }
        switch list.category {
        case .tv:
            if let seasons = item.seasonCount { facts.append("\(seasons) season\(seasons == 1 ? "" : "s")") }
        case .anime:
            if let eps = item.episodeCount, eps > 1 { facts.append("\(eps) episodes") }
        case .manga:
            if let length = MangaLength.text(chapters: item.chapterCount, volumes: item.volumeCount, long: true) {
                facts.append(length)
            }
        case .games:
            if let platforms = item.platforms, !platforms.isEmpty {
                facts.append(platforms.joined(separator: ", "))
            }
        default:
            break
        }
        return facts
    }

    // MARK: Custom lists

    /// Custom lists are the one place the item's details are the user's
    /// own writing rather than catalog facts, so they stay editable.
    /// Maps-linked custom items take their name and address from Maps, so
    /// only the user-defined fields are editable there.
    @ViewBuilder
    private var customDetailsSection: some View {
        if list.category == .custom {
            if !list.linksToMapsLocation {
                Section {
                    TextField("Name", text: nameBinding)
                        .font(.body.weight(.medium))
                    TextField("Link", text: customLinkBinding)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    header("Details")
                }
            }
            if !list.customFieldNames.isEmpty {
                Section {
                    CustomFieldRows(names: list.customFieldNames, value: customFieldBinding)
                } header: {
                    header(list.linksToMapsLocation ? "Details" : "Fields")
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

/// Quiet capsule for the outbound link under the item hero.
private struct HeroActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
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
