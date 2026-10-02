import SwiftUI

/// Sheet flow for creating a new list. Single screen: pick category, name
/// the list, and (for Custom) define metadata field names.
struct CreateListView: View {
    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var category: Category
    /// Custom field rows as typed. Every row counts, so there's no Add
    /// step; the last row is always blank and ready for the next field.
    @State private var fieldDrafts: [FieldDraft] = [FieldDraft()]
    @FocusState private var focusedFieldID: UUID?
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
                        ForEach($fieldDrafts) { $draft in
                            let isTrailingBlank = draft.id == fieldDrafts.last?.id
                            TextField(
                                isTrailingBlank ? (fieldDrafts.count == 1 ? "Add a field, e.g. Region" : "Add another field") : "Field name",
                                text: $draft.name
                            )
                            .textInputAutocapitalization(.words)
                            // Field names are often short labels (ABV, SKU)
                            // that autocorrect would rewrite.
                            .autocorrectionDisabled()
                            .focused($focusedFieldID, equals: draft.id)
                            .submitLabel(.next)
                            .onSubmit { focusRow(after: draft.id) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !isTrailingBlank {
                                    Button(role: .destructive) {
                                        removeField(draft.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
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
        .onChange(of: fieldDrafts) { keepTrailingBlankRow() }
        .onChange(of: focusedFieldID) { dropClearedRows() }
        .presentationBackground(Theme.background)
    }

    private func header(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.textSecondary)
    }

    /// Typing into the blank last row makes it a field, so add a fresh
    /// blank row after it.
    private func keepTrailingBlankRow() {
        if let last = fieldDrafts.last, !last.isBlank {
            withAnimation(Theme.spring) { fieldDrafts.append(FieldDraft()) }
        }
    }

    /// A field cleared and left behind is gone, rather than lingering as a
    /// blank row mid-list.
    private func dropClearedRows() {
        let lastID = fieldDrafts.last?.id
        let cleared = fieldDrafts.filter { $0.isBlank && $0.id != lastID && $0.id != focusedFieldID }
        guard !cleared.isEmpty else { return }
        withAnimation(Theme.spring) {
            fieldDrafts.removeAll { draft in cleared.contains { $0.id == draft.id } }
        }
    }

    private func focusRow(after id: UUID) {
        guard let index = fieldDrafts.firstIndex(where: { $0.id == id }),
              fieldDrafts.indices.contains(index + 1)
        else { return }
        focusedFieldID = fieldDrafts[index + 1].id
    }

    private func removeField(_ id: UUID) {
        withAnimation(Theme.spring) { fieldDrafts.removeAll { $0.id == id } }
    }

    private func save() {
        guard canSave else { return }
        let list = RankList(
            name: name.trimmingCharacters(in: .whitespaces),
            category: category,
            customFieldNames: category == .custom ? FieldDraft.fieldNames(from: fieldDrafts) : [],
            linksToMapsLocation: category == .custom ? linksToMapsLocation : false
        )
        repository.addList(list)
        dismiss()
    }
}

/// One custom field row in the create-list form.
struct FieldDraft: Identifiable, Equatable {
    let id = UUID()
    var name = ""

    var isBlank: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The field names a list is created with: trimmed, blanks dropped, and
    /// duplicates (ignoring case) collapsed to their first spelling, in
    /// order.
    static func fieldNames(from drafts: [FieldDraft]) -> [String] {
        var seen = Set<String>()
        return drafts
            .map { $0.name.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

/// Selectable category tile, used by create-list and import.
struct CategoryChip: View {
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
