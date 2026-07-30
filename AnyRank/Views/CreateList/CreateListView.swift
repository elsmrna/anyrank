import SwiftUI

/// Sheet flow for creating a new list. Single screen: pick category, name
/// the list, and (for Custom) define metadata field names.
struct CreateListView: View {
    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var category: Category = .restaurants
    @State private var customFieldNames: [String] = []
    @State private var newFieldDraft: String = ""
    /// Custom-only toggle: when on, the add-item flow uses the Google
    /// Places picker (same UX as Restaurants/Bars) and items carry the
    /// canonical Maps metadata. Off keeps Custom lists text-only.
    @State private var linksToMapsLocation: Bool = false

    var body: some View {
        Form {
            Section("Name") {
                TextField("e.g. Restaurants — NYC", text: $name)
                    .textInputAutocapitalization(.words)
            }

            Section("Category") {
                Picker("Category", selection: $category) {
                    ForEach(Category.allCases) { c in
                        Label(c.displayName, systemImage: c.systemIconName).tag(c)
                    }
                }
                .pickerStyle(.menu)
            }

            if category == .custom {
                Section {
                    Toggle("Tie items to a Google Maps location", isOn: $linksToMapsLocation)
                } header: {
                    Text("Google Maps")
                } footer: {
                    Text("When on, you'll search Google Maps to add items — the picked place's name, address, and Maps link travel with each item, the same way Restaurants and Bars work. When off, items are free-form text only. Requires Google sign-in.")
                }

                Section("Custom fields") {
                    if customFieldNames.isEmpty {
                        Text("Add optional metadata fields like \"Region\" or \"Vintage\". You can leave this empty.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(customFieldNames, id: \.self) { field in
                            HStack {
                                Text(field)
                                Spacer()
                                Button(role: .destructive) {
                                    customFieldNames.removeAll { $0 == field }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    HStack {
                        TextField("Field name", text: $newFieldDraft)
                        Button("Add") {
                            let trimmed = newFieldDraft.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty, !customFieldNames.contains(trimmed) else { return }
                            customFieldNames.append(trimmed)
                            newFieldDraft = ""
                        }
                        .disabled(newFieldDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .navigationTitle("New list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    save()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let list = RankList(
            name: name.trimmingCharacters(in: .whitespaces),
            category: category,
            customFieldNames: category == .custom ? customFieldNames : [],
            linksToMapsLocation: category == .custom ? linksToMapsLocation : false
        )
        repository.addList(list)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        CreateListView()
    }
    .environment(PreviewSupport.emptyRepository())
}
