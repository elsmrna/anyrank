import SwiftUI

/// Sheet flow for creating a new list. Single screen: pick category, name
/// the list, and (for Custom) define metadata field names.
struct CreateListView: View {
    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var category: Category
    @State private var customFieldNames: [String] = []
    @State private var newFieldDraft: String = ""
    /// Custom-only toggle: when on, the add-item flow uses the Google
    /// Places picker (same UX as Restaurants/Bars) and items carry the
    /// canonical Maps metadata. Off keeps Custom lists text-only.
    @State private var linksToMapsLocation: Bool = false
    @FocusState private var nameFocused: Bool

    init(initialCategory: Category = .restaurants) {
        _category = State(initialValue: initialCategory)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Group {
                Section {
                    TextField(category.namePlaceholder, text: $name)
                        .font(.body.weight(.medium))
                        .textInputAutocapitalization(.words)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { if canSave { save() } }
                } header: {
                    // The category grid lives in the header rather than a row
                    // so the section's rounded mask doesn't clip the chips.
                    VStack(alignment: .leading, spacing: 12) {
                        header("What are you ranking?")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(Category.allCases) { c in
                                CategoryChip(category: c, isSelected: c == category) {
                                    withAnimation(Theme.spring) { category = c }
                                }
                            }
                        }
                        .padding(.bottom, 16)
                        header("Name")
                    }
                    .textCase(nil)
                }

                if category == .custom {
                    Section {
                        Toggle("Look items up on Google Maps", isOn: $linksToMapsLocation)
                    } footer: {
                        Text("Search Google Maps when adding, so each item carries its address and Maps link — just like Restaurants and Bars. Requires Google sign-in.")
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Section {
                        ForEach(customFieldNames, id: \.self) { field in
                            HStack {
                                Text(field)
                                Spacer()
                                Button {
                                    withAnimation(Theme.spring) {
                                        customFieldNames.removeAll { $0 == field }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(field)")
                            }
                        }
                        HStack {
                            TextField("Add a field, e.g. Region", text: $newFieldDraft)
                                .submitLabel(.next)
                                .onSubmit(addField)
                            Button("Add", action: addField)
                                .fontWeight(.semibold)
                                .disabled(newFieldDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } header: {
                        header("Custom fields")
                    } footer: {
                        Text("Optional details to fill in for each item, like \"Vintage\" or \"Grape\".")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .themedList()
        .tint(Theme.accent)
        .navigationTitle("New list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Create list", action: save)
                .buttonStyle(.primary)
                .disabled(!canSave)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 8)
                .background(Theme.background)
        }
        .onAppear { nameFocused = true }
        .presentationBackground(Theme.background)
    }

    private func header(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.textSecondary)
    }

    private func addField() {
        let trimmed = newFieldDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !customFieldNames.contains(trimmed) else { return }
        withAnimation(Theme.spring) { customFieldNames.append(trimmed) }
        newFieldDraft = ""
    }

    private func save() {
        guard canSave else { return }
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

private struct CategoryChip: View {
    let category: Category
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: category.systemIconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.onAccent : category.tint)
                Text(category.displayName)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.accent : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: isSelected ? 0 : 0.5)
            )
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        CreateListView()
    }
    .environment(PreviewSupport.emptyRepository())
}
