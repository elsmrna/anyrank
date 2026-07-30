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
            Section {
                HStack {
                    BucketAccent(bucket: item.bucket)
                        .frame(height: 32)
                    VStack(alignment: .leading) {
                        Text(item.bucket.displayName)
                            .font(.subheadline.weight(.semibold))
                        if item.shouldDisplayScore {
                            Text(String(format: "%.1f", item.score))
                                .font(.title2.bold())
                                .monospacedDigit()
                        } else {
                            Text("Score appears once this bucket has 3 items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Name") {
                TextField("Name", text: nameBinding)
            }

            categoryMetadataSection

            Section("Visited") {
                Toggle("Track date", isOn: dateBinding)
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
            }

            Section("Notes") {
                TextEditor(text: notesBinding)
                    .frame(minHeight: 100)
            }

            if let url = item.primaryURL {
                Section {
                    Link(destination: url) {
                        Label("Open link", systemImage: "arrow.up.right.square")
                    }
                }
            }

            Section {
                Button {
                    rerankPresented = true
                } label: {
                    Label("Re-rank this item", systemImage: "arrow.triangle.2.circlepath")
                }

                Button(role: .destructive) {
                    deleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .navigationTitle(item.name)
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

    @ViewBuilder
    private var categoryMetadataSection: some View {
        switch list.category {
        case .restaurants, .bars:
            Section("Place") {
                if let address = item.address {
                    LabeledContent("Address", value: address)
                }
                if let url = item.mapsURLString {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        case .movies:
            Section("Movie") {
                if let year = item.releaseYear {
                    LabeledContent("Year", value: String(year))
                }
                if let url = item.imdbURLString {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                if let url = item.storyGraphURLString {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                if let url = item.aniListURLString {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                if let url = item.igdbURLString {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                if let url = item.spotifyURLString {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                if let url = item.spotifyURLString {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        case .custom:
            // Maps-linked custom lists show the same Place section as
            // Restaurants/Bars — the address and Maps URL came from the
            // picker, not free-form entry, so they read as static facts
            // rather than editable fields.
            if list.linksToMapsLocation {
                Section("Place") {
                    if let address = item.address {
                        LabeledContent("Address", value: address)
                    }
                    if let url = item.mapsURLString {
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
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
